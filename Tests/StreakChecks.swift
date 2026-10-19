import Foundation

@main @MainActor enum StreakChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checked += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0, in override: Calendar? = nil) -> Date {
            (override ?? calendar).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        var clock = date(2026, 10, 13)
        var suites: [(String, UserDefaults)] = []
        defer { for (suite, defaults) in suites { defaults.removePersistentDomain(forName: suite) } }
        func makeHistory(in override: Calendar? = nil, legacy: Int = 0) -> WorkoutHistory {
            let suite = "SquatForMac.StreakChecks.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            suites.append((suite, defaults))
            defaults.set(legacy, forKey: "totalReps")
            return WorkoutHistory(defaults: defaults, calendar: override ?? calendar, now: { clock })
        }
        func record(_ history: WorkoutHistory, on dates: [Date], mode: String = "face") {
            for date in dates.sorted() { history.recordRep(at: date, mode: mode) }
            if let last = dates.max() { history.finishSession(completed: false, at: last) }
        }

        let empty = makeHistory(legacy: 150)
        check(empty.currentStreak == 0 && empty.activeDayCount == 0, "Empty dated history and undated legacy total do not earn streak days")
        empty.beginSession(mode: "face", at: clock)
        empty.finishSession(completed: false, at: clock)
        check(empty.currentStreak == 0 && empty.activeDayCount == 0, "An uncounted session start does not earn an active day")

        let todayOnly = makeHistory()
        record(todayOnly, on: [clock, date(2026, 10, 13, hour: 13)])
        check(todayOnly.currentStreak == 1 && todayOnly.activeDayCount == 1, "Multiple movements on today count as one streak day")
        clock = date(2026, 10, 14)
        check(todayOnly.currentStreak == 1, "The next day remains an opportunity to continue yesterday's streak")
        clock = date(2026, 10, 15)
        check(todayOnly.currentStreak == 0 && todayOnly.activeDayCount == 1, "A missed whole day breaks the streak but retains the recorded active day")

        clock = date(2026, 10, 13)
        let yesterday = makeHistory()
        record(yesterday, on: [date(2026, 10, 10), date(2026, 10, 11), date(2026, 10, 12)])
        check(yesterday.currentStreak == 3 && yesterday.activeDayCount == 3, "Three days ending yesterday remain current before today's first movement")
        record(yesterday, on: [clock])
        check(yesterday.currentStreak == 4 && yesterday.activeDayCount == 4, "Today's first movement extends yesterday's streak")

        let interrupted = makeHistory()
        record(interrupted, on: [date(2026, 10, 8), date(2026, 10, 9), date(2026, 10, 11), date(2026, 10, 12), clock])
        check(interrupted.currentStreak == 3 && interrupted.activeDayCount == 5, "A gap distinguishes the current streak from total active days")
        let older = makeHistory()
        record(older, on: [date(2026, 10, 10), date(2026, 10, 11)])
        check(older.currentStreak == 0 && older.activeDayCount == 2, "No movement today or yesterday means no current streak")

        let future = makeHistory()
        record(future, on: [clock, date(2026, 10, 14), date(2026, 10, 15)])
        check(future.currentStreak == 1 && future.activeDayCount == 1, "Future calendar dates do not inflate either statistic")
        let demonstration = makeHistory()
        record(demonstration, on: [date(2026, 10, 12)], mode: "demo")
        record(demonstration, on: [clock], mode: "デモ")
        check(demonstration.currentStreak == 0 && demonstration.activeDayCount == 0, "Explicit demonstration sessions do not earn streak days")

        clock = date(2026, 10, 14, hour: 0, minute: 3)
        let midnight = makeHistory()
        record(midnight, on: [date(2026, 10, 13, hour: 23, minute: 59), date(2026, 10, 14, hour: 0, minute: 1)])
        check(midnight.currentStreak == 2 && midnight.activeDayCount == 2, "A session crossing midnight earns each movement's actual calendar day")

        clock = date(2027, 1, 1)
        let newYear = makeHistory()
        record(newYear, on: [date(2026, 12, 30), date(2026, 12, 31), clock])
        check(newYear.currentStreak == 3 && newYear.activeDayCount == 3, "A streak continues across a year boundary")

        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        clock = date(2026, 3, 9, in: dstCalendar)
        let spring = makeHistory(in: dstCalendar)
        record(spring, on: [date(2026, 3, 7, in: dstCalendar), date(2026, 3, 8, in: dstCalendar), clock])
        check(spring.currentStreak == 3 && spring.activeDayCount == 3, "A 23-hour daylight-saving day still counts as one calendar day")
        clock = date(2026, 11, 2, in: dstCalendar)
        let autumn = makeHistory(in: dstCalendar)
        record(autumn, on: [date(2026, 10, 31, in: dstCalendar), date(2026, 11, 1, hour: 1, in: dstCalendar), date(2026, 11, 1, hour: 23, in: dstCalendar), clock])
        check(autumn.currentStreak == 3 && autumn.activeDayCount == 3, "Repeated-clock 25-hour days never count twice")

        let savedDefaults = suites.last!.1
        let restored = WorkoutHistory(defaults: savedDefaults, calendar: dstCalendar, now: { clock })
        check(restored.currentStreak == 3 && restored.activeDayCount == 3, "Both statistics survive relaunch without a storage-format change")
        check(empty.shareDayStatistics().elapsedDays == 0 && empty.shareDayStatistics().bestStreak == 0, "Undated legacy totals and zero-rep sessions cannot establish a start date or best streak")
        clock = date(2026, 10, 13)
        check(todayOnly.shareDayStatistics().elapsedDays == 0 && todayOnly.shareDayStatistics().bestStreak == 1, "First date is zero elapsed days and one streak day; duplicate reps do not duplicate days")
        clock = date(2026, 10, 14)
        check(todayOnly.shareDayStatistics().elapsedDays == 1 && todayOnly.shareDayStatistics().bestStreak == 1, "One calendar day after first use is one elapsed day")
        clock = date(2026, 10, 15)
        check(todayOnly.shareDayStatistics().elapsedDays == 2 && todayOnly.shareDayStatistics().bestStreak == 1, "Elapsed days include inactive days and a broken streak does not erase the best")
        clock = date(2026, 10, 13)
        let personalBest = makeHistory()
        record(personalBest, on: [date(2026,10,1),date(2026,10,2),date(2026,10,3),date(2026,10,4),date(2026,10,5),date(2026,10,11),date(2026,10,12),clock])
        check(personalBest.shareDayStatistics().elapsedDays == 12, "Elapsed is first exercise to today, not active-day count")
        check(personalBest.shareDayStatistics().bestStreak == 5 && personalBest.currentStreak == 3, "Best scans all history rather than the current streak")
        check(future.shareDayStatistics().elapsedDays == 0 && future.shareDayStatistics().bestStreak == 1, "Future dates do not extend either share statistic")
        check(demonstration.shareDayStatistics().elapsedDays == 0 && demonstration.shareDayStatistics().bestStreak == 0, "Demonstration exercise cannot establish share statistics")
        clock = date(2026,10,14,hour:0,minute:3)
        check(midnight.shareDayStatistics().elapsedDays == 1 && midnight.shareDayStatistics().bestStreak == 2, "Midnight uses calendar dates rather than complete 24-hour periods")
        clock = date(2027,1,1)
        check(newYear.shareDayStatistics().elapsedDays == 2 && newYear.shareDayStatistics().bestStreak == 3, "Elapsed and best cross a year boundary")
        clock = date(2026,3,9,in:dstCalendar)
        check(spring.shareDayStatistics().elapsedDays == 2 && spring.shareDayStatistics().bestStreak == 3, "A 23-hour DST day does not shorten elapsed or longest streak")
        clock = date(2026,11,2,in:dstCalendar)
        check(autumn.shareDayStatistics().elapsedDays == 2 && autumn.shareDayStatistics().bestStreak == 3, "A repeated 25-hour day does not add an extra day")
        check(restored.shareDayStatistics().elapsedDays == 2 && restored.shareDayStatistics().bestStreak == 3, "Share statistics survive restart without new persisted fields")
        print("PASS: \(checked) streak checks")
    }
}
