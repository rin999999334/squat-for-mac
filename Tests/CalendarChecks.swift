import Foundation

@main @MainActor enum CalendarChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checked += 1
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0, minute: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
        }
        let october = ContributionCalendarModel(referenceDate: date(2026, 10, 13, hour: 14), calendar: calendar)
        check(october.days.count == 91, "Exactly thirteen complete weeks")
        check(october.firstDate == date(2026, 7, 19) && october.lastDate == date(2026, 10, 17), "October calendar spans Sunday through current Saturday")
        check((0..<13).allSatisfy { calendar.component(.weekday, from: october.days[$0 * 7].date) == 1 }, "Every column starts on Sunday")
        check(october.days.filter(\.isFuture).count == 4, "Future dates are clearly separated")
        check(october.monthLabels.filter { !$0.isEmpty } == ["7月", "8月", "9月", "10月"], "Month labels follow displayed calendar boundaries")
        let populated = ContributionCalendarModel(referenceDate: date(2026, 10, 13), calendar: calendar, counts: [DayCount(date: date(2026, 10, 12), count: 16), DayCount(date: date(2026, 10, 13, hour: 14), count: 8), DayCount(date: date(2026, 10, 14), count: 100)])
        check(populated.days.first { $0.date == date(2026, 10, 13) }?.count == 8, "Count dates normalize to midnight")
        check(populated.days.first { $0.date == date(2026, 10, 14) }?.count == 0, "Future cells cannot display historical-looking counts")
        check([0, 1, 5, 6, 15, 16, 30, 31].map(ContributionCalendarModel.intensity) == [0, 1, 1, 2, 2, 3, 3, 4], "Color thresholds correspond to actual repetitions")
        let newYear = ContributionCalendarModel(referenceDate: date(2027, 1, 1), calendar: calendar)
        check(newYear.firstDate == date(2026, 10, 4) && newYear.lastDate == date(2027, 1, 2), "Year changes preserve week alignment")
        let leapYear = ContributionCalendarModel(referenceDate: date(2024, 3, 1), calendar: calendar)
        check(leapYear.days.contains { $0.date == date(2024, 2, 29) }, "Leap day appears once")
        check(Set(leapYear.days.map(\.date)).count == 91, "Every calendar day is unique")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstReference = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 10))!
        let dst = ContributionCalendarModel(referenceDate: dstReference, calendar: dstCalendar)
        check(dst.days.count == 91 && (0..<91).allSatisfy { dstCalendar.component(.hour, from: dst.days[$0].date) == 0 }, "Daylight-saving transition retains local midnight cells")

        let suite = "SquatForMac.CalendarChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(100, forKey: "totalReps")
        let history = WorkoutHistory(defaults: defaults, calendar: calendar, now: { date(2026, 10, 13) })
        history.beginSession(mode: "face", at: date(2026, 10, 12, hour: 23, minute: 58))
        history.recordRep(at: date(2026, 10, 12, hour: 23, minute: 59), mode: "face")
        history.recordRep(at: date(2026, 10, 13, hour: 0, minute: 1), mode: "face")
        history.recordRep(at: date(2026, 10, 13, hour: 0, minute: 2), mode: "face")
        let range = history.dayCounts(from: date(2026, 10, 11, hour: 15), through: date(2026, 10, 13, hour: 15))
        check(range.map(\.count) == [0, 1, 2], "Range uses calendar dates and excludes undated legacy total")
        check(history.dayCounts(from: date(2026, 10, 13), through: date(2026, 10, 12)).isEmpty, "Reversed range is empty")
        print("PASS: \(checked) contribution calendar checks")
    }
}
