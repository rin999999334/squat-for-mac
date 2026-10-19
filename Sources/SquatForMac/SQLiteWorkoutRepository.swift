import Foundation
import SQLite3

struct HistoryRepEvent: Codable {
    let id: UUID
    let sessionID: UUID
    let recordedAt: Date
}

struct HistorySnapshot {
    var sessions: [WorkoutSession]
    var events: [HistoryRepEvent]
    var legacyTotal: Int
}

struct LegacyHistoryMigration {
    let snapshot: HistorySnapshot
    let rawArchive: Data?
    var calendar: Calendar = .current
}

enum HistoryWrite {
    case session(WorkoutSession)
    case rep(HistoryRepEvent, WorkoutSession)
}

struct HistoryStorageError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Owns its SQLite connection on one queue. The UI never executes SQL directly.
final class SQLiteWorkoutRepository {
    let databaseURL: URL
    private let queue = DispatchQueue(label: "Squat.history.sqlite", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(databaseURL: URL) throws {
        self.databaseURL = databaseURL
        queue.setSpecific(key: queueKey, value: true)
        try queue.sync {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let result = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
            guard result == SQLITE_OK else {
                let failure = error("Open history")
                sqlite3_close(database)
                database = nil
                throw failure
            }
            sqlite3_busy_timeout(database, 1_500)
            do {
                try execute("PRAGMA foreign_keys = ON")
                try execute("PRAGMA journal_mode = WAL")
                try execute("PRAGMA synchronous = FULL")
                try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
                if let version = try metadata("schema_version"), version != "1" {
                    throw HistoryStorageError(message: "Unsupported history database version: \(version)")
                }
                try execute("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, started_at REAL NOT NULL, ended_at REAL NOT NULL, mode TEXT NOT NULL, completed INTEGER NOT NULL CHECK(completed IN (0,1)))")
                try execute("CREATE TABLE IF NOT EXISTS rep_events (id TEXT PRIMARY KEY, session_id TEXT NOT NULL REFERENCES sessions(id), recorded_at REAL NOT NULL)")
                try execute("CREATE INDEX IF NOT EXISTS rep_events_recorded_at ON rep_events(recorded_at)")
                try execute("CREATE INDEX IF NOT EXISTS rep_events_session_id ON rep_events(session_id)")
                try setMetadata("schema_version", "1")
                try validateDatabase()
            } catch {
                sqlite3_close(database)
                database = nil
                throw error
            }
        }
    }

    deinit {
        if DispatchQueue.getSpecific(key: queueKey) == true { _ = sqlite3_close(database) }
        else { queue.sync { _ = sqlite3_close(database) } }
    }

    func isMigrated() throws -> Bool { try queue.sync { try metadata("legacy_migration_v1") == "complete" } }

    func migrateIfNeeded(_ migration: LegacyHistoryMigration) throws -> HistorySnapshot {
        try queue.sync {
            guard try metadata("legacy_migration_v1") != "complete" else { return try loadSnapshot() }
            if let raw = migration.rawArchive { _ = try backup(raw) }
            try transaction {
                // A marker and all legacy rows commit together. Interrupted migrations retry as a whole.
                guard try scalarInt("SELECT COUNT(*) FROM sessions") == 0,
                      try scalarInt("SELECT COUNT(*) FROM rep_events") == 0 else {
                    throw HistoryStorageError(message: "History has records without a migration marker; the original data was retained.")
                }
                for session in migration.snapshot.sessions { try upsert(session) }
                for event in migration.snapshot.events { try insert(event) }
                try setMetadata("legacy_total", String(migration.snapshot.legacyTotal))
                let loaded = try loadSnapshot()
                guard Self.matches(loaded, migration.snapshot, calendar: migration.calendar) else {
                    throw HistoryStorageError(message: "History migration verification failed; original data was retained.")
                }
                try setMetadata("legacy_migration_v1", "complete")
            }
            return try loadSnapshot()
        }
    }

    func load() throws -> HistorySnapshot { try queue.sync { try loadSnapshot() } }

    @discardableResult
    func backupLegacyArchive(_ data: Data) throws -> URL { try queue.sync { try backup(data) } }

    func write(_ operation: HistoryWrite, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async { completion(Result { try self.apply(operation) }) }
    }

    /// Isolated tests use this path; production calls the asynchronous queue above.
    func writeSynchronously(_ operation: HistoryWrite) throws { try queue.sync { try apply(operation) } }

    private func apply(_ operation: HistoryWrite) throws {
        try transaction {
            switch operation {
            case .session(let session): try upsert(session)
            case .rep(let event, let session):
                try upsert(session)
                try insert(event)
            }
        }
    }

    private func upsert(_ session: WorkoutSession) throws {
        try statement("INSERT INTO sessions(id,started_at,ended_at,mode,completed) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET ended_at = MAX(sessions.ended_at,excluded.ended_at), completed = MAX(sessions.completed,excluded.completed)") { query in
            try bind(session.id.uuidString, 1, query)
            try bind(session.startedAt.timeIntervalSince1970, 2, query)
            try bind(session.endedAt.timeIntervalSince1970, 3, query)
            try bind(session.mode, 4, query)
            guard sqlite3_bind_int(query, 5, session.completed ? 1 : 0) == SQLITE_OK else { throw error("Bind completion") }
            try stepDone(query)
        }
    }

    private func insert(_ event: HistoryRepEvent) throws {
        try statement("INSERT INTO rep_events(id,session_id,recorded_at) VALUES(?,?,?) ON CONFLICT(id) DO NOTHING") { query in
            try bind(event.id.uuidString, 1, query)
            try bind(event.sessionID.uuidString, 2, query)
            try bind(event.recordedAt.timeIntervalSince1970, 3, query)
            try stepDone(query)
        }
        if sqlite3_changes(database) == 0 {
            try statement("SELECT session_id,recorded_at FROM rep_events WHERE id=?") { query in
                try bind(event.id.uuidString, 1, query)
                guard sqlite3_step(query) == SQLITE_ROW,
                      text(query, 0) == event.sessionID.uuidString,
                      abs(sqlite3_column_double(query, 1) - event.recordedAt.timeIntervalSince1970) < 0.000001 else {
                    throw HistoryStorageError(message: "A movement event identifier conflicts with an existing record.")
                }
            }
        }
    }

    private func loadSnapshot() throws -> HistorySnapshot {
        var sessions: [WorkoutSession] = []
        var events: [HistoryRepEvent] = []
        try statement("SELECT s.id,s.started_at,s.ended_at,s.mode,s.completed,COUNT(e.id) FROM sessions s LEFT JOIN rep_events e ON s.id=e.session_id GROUP BY s.id ORDER BY s.started_at,s.rowid") { query in
            while true {
                let step = sqlite3_step(query)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW, let id = UUID(uuidString: text(query, 0)) else { throw error("Read sessions") }
                let started = Date(timeIntervalSince1970: sqlite3_column_double(query, 1))
                let ended = Date(timeIntervalSince1970: sqlite3_column_double(query, 2))
                guard started.timeIntervalSince1970.isFinite, ended.timeIntervalSince1970.isFinite, ended >= started else { throw HistoryStorageError(message: "Invalid session dates in history.") }
                sessions.append(WorkoutSession(id: id, startedAt: started, endedAt: ended, reps: Int(sqlite3_column_int64(query, 5)), mode: text(query, 3), completed: sqlite3_column_int(query, 4) != 0))
            }
        }
        try statement("SELECT id,session_id,recorded_at FROM rep_events ORDER BY recorded_at,rowid") { query in
            while true {
                let step = sqlite3_step(query)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW, let id = UUID(uuidString: text(query, 0)), let sessionID = UUID(uuidString: text(query, 1)) else { throw error("Read movement events") }
                let date = Date(timeIntervalSince1970: sqlite3_column_double(query, 2))
                guard date.timeIntervalSince1970.isFinite else { throw HistoryStorageError(message: "Invalid movement date in history.") }
                events.append(HistoryRepEvent(id: id, sessionID: sessionID, recordedAt: date))
            }
        }
        let legacy = Int(try metadata("legacy_total") ?? "0")
        guard let legacy, legacy >= 0 else { throw HistoryStorageError(message: "Invalid legacy total in history.") }
        let sessionMap = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        guard events.allSatisfy({ event in
            guard let session = sessionMap[event.sessionID] else { return false }
            return event.recordedAt >= session.startedAt && event.recordedAt <= session.endedAt
        }) else { throw HistoryStorageError(message: "Movement events do not match their sessions.") }
        return HistorySnapshot(sessions: sessions, events: events, legacyTotal: legacy)
    }

    private func validateDatabase() throws {
        try statement("PRAGMA quick_check") { query in
            guard sqlite3_step(query) == SQLITE_ROW, text(query, 0) == "ok" else { throw HistoryStorageError(message: "History database integrity check failed.") }
        }
        try statement("PRAGMA foreign_key_check") { query in
            guard sqlite3_step(query) == SQLITE_DONE else { throw HistoryStorageError(message: "History database contains unmatched records.") }
        }
    }

    private func backup(_ data: Data) throws -> URL {
        let folder = databaseURL.deletingLastPathComponent().appendingPathComponent("Legacy Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let primary = folder.appendingPathComponent("workoutHistory-v1.json")
        if let existing = try? Data(contentsOf: primary), existing == data { return primary }
        let url = FileManager.default.fileExists(atPath: primary.path)
            ? folder.appendingPathComponent("workoutHistory-v1-\(UUID().uuidString).json") : primary
        try data.write(to: url, options: .atomic)
        return url
    }

    private func metadata(_ key: String) throws -> String? {
        try statement("SELECT value FROM metadata WHERE key=?") { query in
            try bind(key, 1, query)
            let result = sqlite3_step(query)
            if result == SQLITE_DONE { return nil }
            guard result == SQLITE_ROW else { throw error("Read history metadata") }
            return text(query, 0)
        }
    }

    private func setMetadata(_ key: String, _ value: String) throws {
        try statement("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value") { query in
            try bind(key, 1, query); try bind(value, 2, query); try stepDone(query)
        }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        try statement(sql) { query in
            guard sqlite3_step(query) == SQLITE_ROW else { throw error("Read history count") }
            return Int(sqlite3_column_int64(query, 0))
        }
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw error("Write history") }
    }

    private func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK, let query else { throw error("Prepare history query") }
        defer { sqlite3_finalize(query) }
        return try body(query)
    }

    private func bind(_ value: String, _ index: Int32, _ query: OpaquePointer) throws {
        guard sqlite3_bind_text(query, index, value, -1, transient) == SQLITE_OK else { throw error("Bind history text") }
    }

    private func bind(_ value: Double, _ index: Int32, _ query: OpaquePointer) throws {
        guard sqlite3_bind_double(query, index, value) == SQLITE_OK else { throw error("Bind history date") }
    }

    private func stepDone(_ query: OpaquePointer) throws {
        guard sqlite3_step(query) == SQLITE_DONE else { throw error("Commit history record") }
    }

    private func text(_ query: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(query, column).map { String(cString: $0) } ?? ""
    }

    private func error(_ context: String) -> HistoryStorageError {
        HistoryStorageError(message: "\(context): \(database.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable")")
    }

    private static func matches(_ lhs: HistorySnapshot, _ rhs: HistorySnapshot, calendar: Calendar) -> Bool {
        guard lhs.legacyTotal == rhs.legacyTotal, lhs.sessions.count == rhs.sessions.count, lhs.events.count == rhs.events.count else { return false }
        let savedDays = Dictionary(grouping: lhs.events, by: { calendar.startOfDay(for: $0.recordedAt) }).mapValues(\.count)
        let originalDays = Dictionary(grouping: rhs.events, by: { calendar.startOfDay(for: $0.recordedAt) }).mapValues(\.count)
        guard savedDays == originalDays else { return false }
        let sessions = Dictionary(uniqueKeysWithValues: lhs.sessions.map { ($0.id, $0) })
        guard rhs.sessions.allSatisfy({ original in
            guard let saved = sessions[original.id] else { return false }
            return abs(saved.startedAt.timeIntervalSince(original.startedAt)) < 0.000001 && abs(saved.endedAt.timeIntervalSince(original.endedAt)) < 0.000001 && saved.reps == original.reps && saved.mode == original.mode && saved.completed == original.completed
        }) else { return false }
        let events = Dictionary(uniqueKeysWithValues: lhs.events.map { ($0.id, $0) })
        return rhs.events.allSatisfy { original in
            guard let saved = events[original.id] else { return false }
            return saved.sessionID == original.sessionID && abs(saved.recordedAt.timeIntervalSince(original.recordedAt)) < 0.000001
        }
    }
}
