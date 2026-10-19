import Foundation

@main @MainActor enum HistoryChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checked += 1
        }
        let suite = "ThinkAndMove.HistoryChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
        }
        var clock = date(13, 12)
        defaults.set(18, forKey: "totalReps")
        let history = WorkoutHistory(defaults: defaults, calendar: calendar, now: { clock })
        check(history.legacyTotal == 18 && history.lifetimeReps == 18, "Migrate old total once")
        check(history.todayReps == 0 && history.weekCounts.allSatisfy { $0.count == 0 }, "Undated old total must not invent day history")
        check(history.sessions.isEmpty && history.recentSessions.isEmpty, "No demonstration or placeholder records")
        check(history.dailyGoal == 30, "Default daily target")
        history.dailyGoal = 45
        history.beginSession(mode: "face", at: date(13, 12))
        check(history.todaySessions == 0, "Uncounted starts aren't workout achievements")
        history.recordRep(at: date(13, 12, 0, 10), mode: "face")
        history.recordRep(at: date(13, 12, 0, 20), mode: "face")
        clock = date(13, 12, 0, 30)
        check(history.todayReps == 2 && history.todaySessions == 1, "Counts and session stats update immediately")
        check(history.todayDuration == 30, "Active duration uses clock refresh")
        check(defaults.integer(forKey: "totalReps") == 18, "Legacy defaults remain read-only after SQLite migration")

        let recovered = WorkoutHistory(defaults: defaults, calendar: calendar, now: { clock })
        check(recovered.todayReps == 2 && recovered.lifetimeReps == 20 && recovered.dailyGoal == 45, "Counts, goal and migration survive relaunch")
        clock = date(13, 16)
        check(recovered.todayDuration == 20, "Crash recovery ends partial session at last persisted observation")
        check(recovered.recentSessions.count == 1 && !recovered.recentSessions[0].completed, "Partial sessions remain in history")
        recovered.beginSession(mode: "face", at: date(13, 23, 59, 50))
        recovered.recordRep(at: date(13, 23, 59, 55), mode: "face")
        recovered.recordRep(at: date(14, 0, 0, 5), mode: "face")
        recovered.finishSession(completed: true, at: date(14, 0, 0, 10))
        clock = date(14, 12)
        check(recovered.todayReps == 1 && recovered.todaySessions == 1, "Midnight counts belong to their own calendar date")
        check(recovered.yesterdayReps == 3, "Yesterday uses dated events across midnight")
        check(recovered.todayDuration == 10, "Midnight duration splits at calendar boundary")
        check(recovered.weekCounts.map(\.count).suffix(2) == [3, 1], "Week graph includes both sides of midnight")
        check(recovered.weekCounts.count == 7 && recovered.weekCounts.first?.date == date(8, 0), "Week graph includes chronological last seven calendar days")
        check(recovered.recentSessions[0].completed && recovered.recentSessions[0].reps == 2, "Finished result preserves reps and completion")

        let again = WorkoutHistory(defaults: defaults, calendar: calendar, now: { clock })
        check(again.lifetimeReps == 22 && again.legacyTotal == 18, "Reopening never migrates already-recorded counts twice")
        again.recordRep(at: date(14, 12), mode: "face")
        again.recordRep(at: date(14, 12, 0, 10), mode: "squat")
        check(again.sessions.suffix(2).map(\.mode) == ["face", "squat"], "Mode changes finish old session and begin the correct mode")
        again.finishSession(completed: false, at: date(14, 12, 0, 20))
        again.finishSession(completed: false, at: date(14, 12, 0, 40))
        check(again.sessions.last?.endedAt == date(14, 12, 0, 20), "Repeated finish does not extend an inactive session")
        again.dailyGoal = 0
        check(again.dailyGoal == 1 && defaults.integer(forKey: "thinkAndMove.dailyGoal") == 1, "Target validation persists corrected value")

        let broken = Data("unreadable archived history".utf8)
        let recoverySuite = "ThinkAndMove.HistoryRecoveryChecks.\(UUID().uuidString)"
        let recoveryDefaults = UserDefaults(suiteName: recoverySuite)!
        defer { recoveryDefaults.removePersistentDomain(forName: recoverySuite) }
        recoveryDefaults.set(24, forKey: "totalReps")
        recoveryDefaults.set(broken, forKey: "thinkAndMove.workoutHistory.v1")
        let repaired = WorkoutHistory(defaults: recoveryDefaults, calendar: calendar, now: { clock })
        check(repaired.recoveryMessage != nil && repaired.lifetimeReps == 24 && !repaired.canRecord, "Unreadable data preserves known lifetime count and blocks recording")
        let backup = repaired.databaseURL.deletingLastPathComponent().appendingPathComponent("Legacy Backups/workoutHistory-v1.json")
        check((try? Data(contentsOf: backup)) == broken, "Unreadable original survives intact in local recovery storage")
        repaired.recordRep(at: date(14, 12, 0, 30), mode: "face")
        check(repaired.todayReps == 0 && repaired.lifetimeReps == 24, "Unreadable migration cannot silently start a new empty history")
        // Simulate an explicit recovery of the legacy source, then retry the same migration.
        recoveryDefaults.removeObject(forKey: "thinkAndMove.workoutHistory.v1")
        repaired.retryPendingWrites()
        repaired.recordRep(at: date(14, 12, 0, 30), mode: "face")
        for minute in 1...6 {
            repaired.beginSession(mode: "face", at: date(14, 13, minute))
            repaired.recordRep(at: date(14, 13, minute, 5), mode: "face")
            repaired.finishSession(completed: true, at: date(14, 13, minute, 10))
        }
        repaired.beginSession(mode: "face", at: date(14, 14))
        repaired.finishSession(completed: false, at: date(14, 14, 1))
        check(repaired.recentSessions.count == 5 && repaired.recentSessions.first?.startedAt == date(14, 13, 6), "Recent history keeps newest five counted sessions and ignores empty starts")
        print("PASS: \(checked) workout history checks")
    }
}
