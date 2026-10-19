import Foundation
import SQLite3

@main @MainActor enum SQLiteHistoryChecks {
    struct LegacyEvent: Codable { let sessionID: UUID; let recordedAt: Date }
    struct LegacyArchive: Codable {
        let version: Int
        let sessions: [WorkoutSession]
        let events: [LegacyEvent]
        let activeSessionID: UUID?
        let legacyTotal: Int
    }

    static func main() async throws {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checked += 1
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SquatSQLiteChecks-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var suites: [String] = []
        defer { for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) } }
        func defaults() -> UserDefaults {
            let suite = "Squat.SQLiteChecks.\(UUID().uuidString)"
            suites.append(suite)
            return UserDefaults(suiteName: suite)!
        }
        func sql(_ url: URL, _ statement: String) throws {
            var connection: OpaquePointer?
            guard sqlite3_open(url.path, &connection) == SQLITE_OK else { throw HistoryStorageError(message: "Test database open failed") }
            defer { sqlite3_close(connection) }
            guard sqlite3_exec(connection, statement, nil, nil, nil) == SQLITE_OK else {
                throw HistoryStorageError(message: String(cString: sqlite3_errmsg(connection)))
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 59, second: 59))!
        let next = start.addingTimeInterval(2.1234567)
        let sessionID = UUID()
        let session = WorkoutSession(id: sessionID, startedAt: start, endedAt: next, reps: 2, mode: "face", completed: false)
        let archive = LegacyArchive(version: 1, sessions: [session], events: [LegacyEvent(sessionID: sessionID, recordedAt: start), LegacyEvent(sessionID: sessionID, recordedAt: next)], activeSessionID: sessionID, legacyTotal: 18)
        let raw = try JSONEncoder().encode(archive)
        let migratedDefaults = defaults()
        migratedDefaults.set(raw, forKey: "thinkAndMove.workoutHistory.v1")
        let url = folder.appendingPathComponent("migrated.sqlite")
        let migrated = WorkoutHistory(defaults: migratedDefaults, calendar: calendar, now: { next }, databaseURL: url)
        check(migrated.canRecord && migrated.saveState == .recorded, "Valid legacy archive migrates atomically")
        check(migrated.sessions.first?.id == sessionID && migrated.lifetimeReps == 20 && migrated.legacyTotal == 18, "Session identity and undated total survive migration")
        check(migrated.todayReps == 1 && migrated.yesterdayReps == 1, "Individual movement dates retain midnight day totals")
        check(abs(migrated.sessions[0].endedAt.timeIntervalSince(next)) < 0.000001, "Fractional timestamps retain microsecond precision")
        check((try? Data(contentsOf: folder.appendingPathComponent("Legacy Backups/workoutHistory-v1.json"))) == raw, "Migration preserves the exact raw archive")
        check(migratedDefaults.data(forKey: "thinkAndMove.workoutHistory.v1") == raw, "SQLite migration does not overwrite the legacy source")
        migratedDefaults.set(Data("stale broken archive".utf8), forKey: "thinkAndMove.workoutHistory.v1")
        let restored = WorkoutHistory(defaults: migratedDefaults, calendar: calendar, now: { next }, databaseURL: url)
        check(restored.canRecord && restored.lifetimeReps == 20 && restored.sessions.count == 1, "Committed migration marker prevents duplicate import and ignores stale legacy backup")
        check(restored.todayDuration < 2, "A recovered active session ends at its last recorded observation")

        let directURL = folder.appendingPathComponent("idempotent.sqlite")
        let repository = try SQLiteWorkoutRepository(databaseURL: directURL)
        _ = try repository.migrateIfNeeded(LegacyHistoryMigration(snapshot: HistorySnapshot(sessions: [], events: [], legacyTotal: 0), rawArchive: nil))
        let event = HistoryRepEvent(id: UUID(), sessionID: sessionID, recordedAt: next)
        try repository.writeSynchronously(.rep(event, session))
        try repository.writeSynchronously(.rep(event, session))
        let duplicated = try repository.load()
        check(duplicated.events.count == 1 && duplicated.sessions[0].reps == 1, "Retrying a committed UUID never counts twice")
        var completedSession = session
        completedSession.completed = true
        try repository.writeSynchronously(.session(completedSession))
        try repository.writeSynchronously(.rep(event, session))
        let retriedAfterFinish = try repository.load()
        check(retriedAfterFinish.events.count == 1 && retriedAfterFinish.sessions[0].completed, "Retrying an older event cannot revert a committed completed session")
        do {
            try repository.writeSynchronously(.rep(HistoryRepEvent(id: event.id, sessionID: sessionID, recordedAt: start), session))
            preconditionFailure("Conflicting event payload must fail")
        } catch {
            let afterConflict = try repository.load()
            check(afterConflict.events.count == 1, "A conflicting event UUID is rejected without changing history")
        }

        let failedURL = folder.appendingPathComponent("failed-write.sqlite")
        let failed = WorkoutHistory(defaults: defaults(), calendar: calendar, now: { next }, databaseURL: failedURL)
        failed.beginSession(mode: "face", at: start)
        try sql(failedURL, "CREATE TRIGGER reject_reps BEFORE INSERT ON rep_events BEGIN SELECT RAISE(ABORT,'Simulated storage failure'); END")
        failed.recordRep(at: next, mode: "face")
        failed.finishSession(completed: true, at: next)
        check(failed.todayReps == 1 && failed.saveState == .failed && !failed.canRecord && failed.hasPendingWrites, "Failed commit retains the observed count and pending operation while blocking new recording")
        let committedBeforeRetry = try SQLiteWorkoutRepository(databaseURL: failedURL).load()
        check(committedBeforeRetry.events.isEmpty, "A failed event transaction does not partially commit")
        failed.recordRep(at: next, mode: "face")
        check(failed.todayReps == 1, "New count attempts cannot grow a failed save queue")
        let failedFlush = await failed.flush()
        check(!failedFlush, "Flush reports a failed commit instead of claiming success")
        try sql(failedURL, "DROP TRIGGER reject_reps")
        failed.retryPendingWrites()
        let retryFlush = await failed.flush()
        check(retryFlush && failed.canRecord && failed.saveState == .recorded && !failed.hasPendingWrites, "Retry commits all pending operations and clears the error")
        failed.retryPendingWrites()
        let committed = try SQLiteWorkoutRepository(databaseURL: failedURL).load()
        check(committed.events.count == 1 && committed.sessions[0].completed, "Repeated retry and finish preserve one event and the completed session")

        let asynchronousURL = folder.appendingPathComponent("async.sqlite")
        let asynchronous = WorkoutHistory(defaults: defaults(), calendar: calendar, now: { next }, databaseURL: asynchronousURL, synchronousWrites: false)
        asynchronous.beginSession(mode: "face", at: start)
        for _ in 0..<5 { asynchronous.recordRep(at: next, mode: "face") }
        asynchronous.finishSession(completed: true, at: next)
        check(asynchronous.todayReps == 5 && asynchronous.saveState == .pending && asynchronous.hasPendingWrites, "UI counts update immediately while background commits remain pending")
        let asyncFlush = await asynchronous.flush()
        let asyncSnapshot = try SQLiteWorkoutRepository(databaseURL: asynchronousURL).load()
        check(asyncFlush && asynchronous.saveState == .recorded && asyncSnapshot.events.count == 5, "Flush waits for every serial transaction before reporting five saved counts")
        asynchronous.recordRep(at: next, mode: "demo")
        asynchronous.beginSession(mode: "デモ", at: next)
        check(asynchronous.lifetimeReps == 5 && asynchronous.sessions.count == 1, "Explicit demonstrations never enter SQLite history")

        let retryingURL = folder.appendingPathComponent("async-retry.sqlite")
        let retrying = WorkoutHistory(defaults: defaults(), calendar: calendar, now: { next }, databaseURL: retryingURL, synchronousWrites: false)
        try sql(retryingURL, "CREATE TRIGGER reject_reps BEFORE INSERT ON rep_events BEGIN SELECT RAISE(ABORT,'Simulated asynchronous storage failure'); END")
        retrying.recordRep(at: next, mode: "face")
        let initialRetryFlush = await retrying.flush()
        check(!initialRetryFlush && !retrying.canRecord, "An asynchronous failure blocks new recording")
        try sql(retryingURL, "DROP TRIGGER reject_reps")
        retrying.retryPendingWrites()
        check(!retrying.canRecord && retrying.hasPendingWrites, "Retry cannot re-enable recording before its transaction commits")
        let recoveredRetryFlush = await retrying.flush()
        check(recoveredRetryFlush && retrying.canRecord && retrying.lifetimeReps == 1, "A committed asynchronous retry re-enables recording once")

        let brokenDefaults = defaults()
        let broken = Data("invalid legacy".utf8)
        brokenDefaults.set(broken, forKey: "thinkAndMove.workoutHistory.v1")
        brokenDefaults.set(47, forKey: "totalReps")
        let brokenURL = folder.appendingPathComponent("corrupt/broken.sqlite")
        let brokenHistory = WorkoutHistory(defaults: brokenDefaults, databaseURL: brokenURL)
        check(!brokenHistory.canRecord && brokenHistory.storageError != nil && brokenHistory.lifetimeReps == 47, "Malformed legacy data remains blocked with its known undated total")
        let emptyFailedFlush = await brokenHistory.flush()
        check(emptyFailedFlush && !brokenHistory.hasPendingWrites && brokenHistory.saveState == .failed,
              "Read failure with no new writes permits quit without pretending the database recovered")
        check((try? Data(contentsOf: brokenURL.deletingLastPathComponent().appendingPathComponent("Legacy Backups/workoutHistory-v1.json"))) == broken, "Malformed source is backed up before migration fails")
        let markedMigrated = try SQLiteWorkoutRepository(databaseURL: brokenURL).isMigrated()
        check(!markedMigrated, "A failed legacy import never writes the completion marker")
        let invalidURL = folder.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: invalidURL)
        let unavailable = WorkoutHistory(defaults: defaults(), databaseURL: invalidURL.appendingPathComponent("workout.sqlite"))
        check(!unavailable.canRecord && unavailable.saveState == .failed, "An unavailable database path blocks recording and reports failure")
        let unavailableFlush = await unavailable.flush()
        check(unavailableFlush && !unavailable.hasPendingWrites,
              "An unavailable database never traps a user who has no unsaved operations")
        print("PASS: \(checked) SQLite history checks")
    }
}
