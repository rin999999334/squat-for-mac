import Foundation
import Combine

struct WorkoutSession: Codable, Identifiable {
    let id: UUID
    let startedAt: Date
    var endedAt: Date
    var reps: Int
    let mode: String
    var completed: Bool
}

struct DayCount: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
}

enum HistorySaveState: Equatable {
    case pending
    case notApplicable
    case recorded
    case failed
}

/// Stores real movement counts locally. Camera frames and demonstration counts never enter this store.
/// Old `totalReps` values are retained as an undated total, never assigned to today's history.
@MainActor
final class WorkoutHistory: ObservableObject {
    @Published private(set) var sessions: [WorkoutSession] = []
    @Published private(set) var legacyTotal = 0
    @Published private(set) var recoveryMessage: String?
    @Published private(set) var saveState: HistorySaveState = .recorded
    @Published private(set) var hasPendingWrites = false
    @Published private(set) var storageError: String?
    /// Invalidates count projections only; saving status and pointer activity do not change it.
    @Published private(set) var historyRevision = 0
    private(set) var dayCountIndexRebuildCount = 0
    private(set) var dayCountQueryCount = 0
    @Published var dailyGoal: Int {
        didSet {
            let safeGoal = min(500, max(1, dailyGoal))
            if dailyGoal != safeGoal { dailyGoal = safeGoal }
            defaults.set(safeGoal, forKey: Self.goalKey)
        }
    }

    private struct LegacyRepEvent: Codable {
        let sessionID: UUID
        let recordedAt: Date
    }

    private struct Archive: Codable {
        let version: Int
        let sessions: [WorkoutSession]
        let events: [LegacyRepEvent]
        let activeSessionID: UUID?
        let legacyTotal: Int
    }

    private static let storageKey = "thinkAndMove.workoutHistory.v1"
    private static let migrationKey = "thinkAndMove.legacyTotal.v1"
    private static let goalKey = "thinkAndMove.dailyGoal"
    private static var isolatedDatabaseURLs: [ObjectIdentifier: (UserDefaults, URL)] = [:]
    private let defaults: UserDefaults
    private var calendar: Calendar
    private let now: () -> Date
    private var events: [HistoryRepEvent] = []
    private var dailyCounts: [Date: Int] = [:]
    private var dailySessionIDs: [Date: Set<UUID>] = [:]
    private var realMovementDays = Set<Date>()
    private var activeSessionID: UUID?
    private var repository: SQLiteWorkoutRepository?
    private var pendingWrites: [HistoryWrite] = []
    private var writing = false
    private var retryingFailedWrites = false
    private var flushWaiters: [(Bool) -> Void] = []
    private let synchronousWrites: Bool
    let databaseURL: URL
    private var loaded = false

    var canRecord: Bool { loaded && storageError == nil && !retryingFailedWrites }
    var calendarTimeZone: TimeZone { calendar.timeZone }
    var currentDate: Date { now() }

    func refreshCalendarForCurrentTimeZone(_ timeZone: TimeZone = .current) {
        guard calendar.timeZone != timeZone else { return }
        calendar.timeZone = timeZone
        rebuildDayCountIndex()
    }

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current, now: @escaping () -> Date = Date.init, databaseURL: URL? = nil, synchronousWrites: Bool? = nil) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.databaseURL = databaseURL ?? Self.resolveDatabaseURL(defaults: defaults)
        self.synchronousWrites = synchronousWrites ?? (defaults !== UserDefaults.standard)
        let savedGoal = defaults.object(forKey: Self.goalKey) as? Int ?? 30
        dailyGoal = min(500, max(1, savedGoal))

        loadStorage()
    }

    var lifetimeReps: Int { legacyTotal + events.count }

    var todayReps: Int {
        count(on: calendar.startOfDay(for: now()))
    }

    var yesterdayReps: Int {
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now())) else { return 0 }
        return count(on: yesterday)
    }

    /// Today stays available to continue a streak that currently ends yesterday.
    var currentStreak: Int {
        let today = calendar.startOfDay(for: now())
        let days = recordedDays(through: today)
        guard var date = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var streak = 0
        while days.contains(date) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date), previous < date else { break }
            date = previous
        }
        return streak
    }

    /// Unique local dates with a real recorded movement; undated totals are excluded.
    var activeDayCount: Int {
        recordedDays(through: calendar.startOfDay(for: now())).count
    }

    /// Read-only share statistics, computed from real movement dates in the history's calendar.
    /// Elapsed days are zero on the first movement date; legacy undated counts are excluded.
    func shareDayStatistics() -> (elapsedDays: Int, bestStreak: Int) {
        let today = calendar.startOfDay(for: now())
        let days = recordedDays(through: today).sorted()
        guard let first = days.first else { return (0, 0) }
        let elapsed = max(0, calendar.dateComponents([.day], from: first, to: today).day ?? 0)
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            run = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day ? run + 1 : 1
            best = max(best, run); previous = day
        }
        return (elapsed, best)
    }

    /// Sessions with at least one real count today; a session across midnight can appear on both days.
    var todaySessions: Int {
        dailySessionIDs[calendar.startOfDay(for: now()), default: []].count
    }

    /// Actual session seconds within the current calendar day. A view timer refreshes the active value.
    var todayDuration: TimeInterval {
        let currentTime = now()
        let start = calendar.startOfDay(for: currentTime)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return sessions.reduce(0) { result, session in
            let sessionEnd = session.id == activeSessionID ? max(session.endedAt, currentTime) : session.endedAt
            return result + max(0, min(end, sessionEnd).timeIntervalSince(max(start, session.startedAt)))
        }
    }

    var weekCounts: [DayCount] {
        let today = calendar.startOfDay(for: now())
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return DayCount(date: date, count: count(on: date))
        }
    }

    /// Inclusive calendar dates, using only individually recorded movement events.
    func dayCounts(from firstDate: Date, through lastDate: Date) -> [DayCount] {
        let start = calendar.startOfDay(for: firstDate)
        let last = calendar.startOfDay(for: lastDate)
        guard start <= last else { return [] }
        dayCountQueryCount += 1
        var days: [DayCount] = []
        var date = start
        while date <= last {
            days.append(DayCount(date: date, count: dailyCounts[date, default: 0]))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        return days
    }

    var recentSessions: [WorkoutSession] {
        Array(sessions.filter { $0.reps > 0 }.sorted { $0.startedAt > $1.startedAt }.prefix(5))
    }

    func beginSession(mode: String, at date: Date = Date()) {
        guard canRecord, mode != "demo", mode != "デモ" else { return }
        if activeSessionID != nil { finishSession(completed: false, at: date) }
        let session = WorkoutSession(id: UUID(), startedAt: date, endedAt: date, reps: 0, mode: mode, completed: false)
        sessions.append(session)
        activeSessionID = session.id
        enqueue(.session(session))
    }

    func recordRep(at date: Date = Date(), mode: String) {
        guard canRecord, mode != "demo", mode != "デモ" else { return }
        if let id = activeSessionID,
           let session = sessions.first(where: { $0.id == id }),
           session.mode != mode {
            finishSession(completed: false, at: date)
        }
        if activeSessionID == nil { beginSession(mode: mode, at: date) }
        guard let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        // Count observations cannot precede the current session or its previous observation.
        let observedAt = max(date, sessions[index].endedAt)
        sessions[index].reps += 1
        sessions[index].endedAt = observedAt
        let event = HistoryRepEvent(id: UUID(), sessionID: id, recordedAt: observedAt)
        events.append(event)
        self.index(event, isRealMovement: true)
        historyRevision &+= 1
        enqueue(.rep(event, sessions[index]))
    }

    func finishSession(completed: Bool, at date: Date = Date()) {
        guard let id = activeSessionID, let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].endedAt = max(date, sessions[index].endedAt)
        sessions[index].completed = completed
        activeSessionID = nil
        enqueue(.session(sessions[index]))
    }

    func count(on start: Date) -> Int {
        dailyCounts[start, default: 0]
    }

    private func recordedDays(through today: Date) -> Set<Date> {
        Set(realMovementDays.filter { $0 <= today })
    }

    private func index(_ event: HistoryRepEvent, isRealMovement: Bool) {
        let day = calendar.startOfDay(for: event.recordedAt)
        dailyCounts[day, default: 0] += 1
        dailySessionIDs[day, default: []].insert(event.sessionID)
        if isRealMovement { realMovementDays.insert(day) }
    }

    private func rebuildDayCountIndex() {
        dailyCounts.removeAll(keepingCapacity: true)
        dailySessionIDs.removeAll(keepingCapacity: true)
        realMovementDays.removeAll(keepingCapacity: true)
        let demonstrationIDs = Set(sessions.filter { $0.mode == "demo" || $0.mode == "デモ" }.map(\.id))
        for event in events { index(event, isRealMovement: !demonstrationIDs.contains(event.sessionID)) }
        dayCountIndexRebuildCount += 1
        historyRevision &+= 1
    }

    /// Completion is called only after every queued SQL transaction has committed, or a failure is known.
    /// The application uses this to defer termination without blocking the main thread.
    func flush(completion: @escaping (Bool) -> Void) {
        // A read failure must not trap the user in the app when no new writes
        // exist. Pending writes still require a successful commit before quit.
        guard hasPendingWrites else { completion(true); return }
        if storageError != nil { completion(false); return }
        flushWaiters.append(completion)
    }

    func flush() async -> Bool {
        await withCheckedContinuation { continuation in
            flush { continuation.resume(returning: $0) }
        }
    }

    func retryPendingWrites() {
        guard !writing else { return }
        let wasFailed = storageError != nil
        storageError = nil
        recoveryMessage = nil
        if !loaded {
            loadStorage()
        } else {
            retryingFailedWrites = !pendingWrites.isEmpty && (wasFailed || retryingFailedWrites)
            saveState = pendingWrites.isEmpty ? .recorded : .pending
            writeNext()
        }
    }

    private func enqueue(_ operation: HistoryWrite) {
        pendingWrites.append(operation)
        hasPendingWrites = true
        saveState = storageError == nil ? .pending : .failed
        writeNext()
    }

    private func writeNext() {
        guard !writing, storageError == nil, let operation = pendingWrites.first, let repository else { return }
        writing = true
        if synchronousWrites {
            didWrite(Result { try repository.writeSynchronously(operation) })
        } else {
            repository.write(operation) { [weak self] result in
                Task { @MainActor in self?.didWrite(result) }
            }
        }
    }

    private func didWrite(_ result: Result<Void, Error>) {
        writing = false
        switch result {
        case .success:
            if !pendingWrites.isEmpty { pendingWrites.removeFirst() }
            hasPendingWrites = !pendingWrites.isEmpty
            if !hasPendingWrites { retryingFailedWrites = false }
            saveState = hasPendingWrites ? .pending : .recorded
            if hasPendingWrites { writeNext() } else { finishFlush(success: true) }
        case .failure(let error):
            // Keep the exact operation, including its event UUID, for idempotent retry.
            storageError = error.localizedDescription
            retryingFailedWrites = true
            recoveryMessage = "履歴を保存できませんでした。再試行してください。元の記録と未保存の回数は保持しています。"
            saveState = .failed
            finishFlush(success: false)
        }
    }

    private func finishFlush(success: Bool) {
        let waiters = flushWaiters
        flushWaiters.removeAll()
        for waiter in waiters { waiter(success) }
    }

    private func loadStorage() {
        defer { rebuildDayCountIndex() }
        do {
            let repository = try SQLiteWorkoutRepository(databaseURL: databaseURL)
            self.repository = repository
            let snapshot: HistorySnapshot
            if try repository.isMigrated() {
                // The SQLite marker is the authority. A stale legacy backup is never imported again.
                snapshot = try repository.load()
            } else {
                let raw = defaults.data(forKey: Self.storageKey)
                var legacy = max(0, defaults.object(forKey: Self.migrationKey) as? Int ?? defaults.integer(forKey: "totalReps"))
                var oldSessions: [WorkoutSession] = []
                var oldEvents: [HistoryRepEvent] = []
                if let raw {
                    _ = try repository.backupLegacyArchive(raw)
                    let archive: Archive
                    do {
                        archive = try JSONDecoder().decode(Archive.self, from: raw)
                        guard Self.isValid(archive) else { throw HistoryError.invalidArchive }
                    } catch {
                        legacyTotal = max(0, defaults.integer(forKey: "totalReps"), defaults.integer(forKey: Self.migrationKey))
                        throw HistoryStorageError(message: "The legacy history could not be read. Its original data was backed up and recording is paused.")
                    }
                    legacy = archive.legacyTotal
                    oldSessions = archive.sessions
                    oldEvents = archive.events.map { HistoryRepEvent(id: UUID(), sessionID: $0.sessionID, recordedAt: $0.recordedAt) }
                    // A failed migration can still show the original dated history, but cannot add counts.
                    sessions = oldSessions
                    events = oldEvents
                    legacyTotal = legacy
                }
                snapshot = try repository.migrateIfNeeded(LegacyHistoryMigration(snapshot: HistorySnapshot(sessions: oldSessions, events: oldEvents, legacyTotal: legacy), rawArchive: raw, calendar: calendar))
            }
            sessions = snapshot.sessions
            events = snapshot.events
            legacyTotal = snapshot.legacyTotal
            activeSessionID = nil
            loaded = true
            storageError = nil
            recoveryMessage = nil
            saveState = .recorded
        } catch {
            storageError = error.localizedDescription
            recoveryMessage = "履歴を読み込めませんでした。元のデータを保管しています。記録を始める前に再試行してください。"
            saveState = .failed
            loaded = false
        }
    }

    private static func resolveDatabaseURL(defaults: UserDefaults) -> URL {
        if defaults === UserDefaults.standard {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            return support.appendingPathComponent("Squat", isDirectory: true).appendingPathComponent("workout.sqlite")
        }
        // Test suites must never read or alter the user's real workout database.
        let identity = ObjectIdentifier(defaults)
        if let entry = isolatedDatabaseURLs[identity] { return entry.1 }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SquatHistoryChecks-\(UUID().uuidString)", isDirectory: true).appendingPathComponent("workout.sqlite")
        isolatedDatabaseURLs[identity] = (defaults, url)
        return url
    }

    private enum HistoryError: Error { case invalidArchive }

    private static func isValid(_ archive: Archive) -> Bool {
        guard archive.version == 1, archive.legacyTotal >= 0 else { return false }
        let ids = Set(archive.sessions.map(\.id))
        guard ids.count == archive.sessions.count,
              archive.activeSessionID.map({ ids.contains($0) }) ?? true else { return false }
        let eventsBySession = Dictionary(grouping: archive.events, by: \.sessionID)
        guard archive.events.allSatisfy({ ids.contains($0.sessionID) && $0.recordedAt.timeIntervalSinceReferenceDate.isFinite }) else { return false }
        return archive.sessions.allSatisfy { session in
            session.reps >= 0 && session.reps == eventsBySession[session.id, default: []].count
                && session.startedAt.timeIntervalSinceReferenceDate.isFinite
                && session.endedAt.timeIntervalSinceReferenceDate.isFinite
                && session.endedAt >= session.startedAt
                && eventsBySession[session.id, default: []].allSatisfy { $0.recordedAt >= session.startedAt && $0.recordedAt <= session.endedAt }
        }
    }
}
