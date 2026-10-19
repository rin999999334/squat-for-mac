import Foundation

@main struct ProgressRenderingChecks {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) { guard condition() else { fatalError(description) }; checks += 1 }
        let calendar = ProgressCalendarModel.localCalendar(timeZone: TimeZone(identifier: "Asia/Tokyo")!)
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
        let today = date(2026, 10, 15)
        let counts = [date(2026, 1, 1): 5, date(2026, 10, 15): 100, date(2026, 12, 31): 10000]
        let model = ProgressCalendarModel(period: .year, anchor: today, counts: counts, today: today, calendar: calendar)
        let cache = ProgressRenderCache()
        let snapshot = cache.snapshot(model: model, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
        check(snapshot.days.count == 365 && snapshot.dayLookup.count == 365, "Year renders every date once")
        check(cache.snapshotBuildCount == 1 && cache.dayLabelBuildCount == 365, "Initial snapshot formats only one year")
        check(snapshot.weeklyMaximum == 100, "Visible bar maximum excludes future imported counts")
        check(snapshot.model.annualMaximum == 100, "Future timestamps do not alter annual intensity")
        check(snapshot.dayLookup[today]?.accessibilityLabel.contains("100 repetitions") == true, "Day labels retain actual counts")
        check(snapshot.dayLookup[today]?.detailLabel == "Oct 15 · 100 reps", "Compact English footer retains month, day and exact count")
        check(snapshot.dayLookup[today]?.accessibilityLabel.contains("2026") == true, "The compact footer preserves the full year in accessibility text")
        check(snapshot.dayLookup[date(2026, 12, 31)]?.detailLabel == "Dec 31 · Future", "Future footer retains its date without showing imported counts")
        check(snapshot.monthLabels.filter { !$0.isEmpty }.count == 12, "Month headers are preformatted once")
        for index in 0..<2000 {
            let cached = cache.snapshot(model: model, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
            _ = cached.dayLookup[model.days[index % 365].date]
        }
        check(cache.snapshotBuildCount == 1 && cache.dayLabelBuildCount == 365, "Two thousand hover/selection reads never rebuild or reformat the year")
        let month = ProgressCalendarModel(period: .month, anchor: today, counts: counts, today: today, calendar: calendar)
        _ = cache.snapshot(model: month, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
        _ = cache.snapshot(model: model, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
        check(cache.snapshotBuildCount == 2 && cache.dayLabelBuildCount == 396, "Switching back to an existing period reuses its snapshot")
        let japanese = cache.snapshot(model: model, revision: 1, japanese: true, locale: Locale(identifier: "ja_JP"))
        check(japanese.dayLookup[today]?.accessibilityLabel.contains("100回") == true && japanese.days[0].weekdayLabel == "Thu", "Details localize while weekday labels stay English")
        check(japanese.dayLookup[today]?.detailLabel == "10月15日 · 100回", "Compact Japanese footer retains month, day and exact count")
        var updated = counts; updated[today] = 101
        let fresh = ProgressCalendarModel(period: .year, anchor: today, counts: updated, today: today, calendar: calendar)
        let updatedSnapshot = cache.snapshot(model: fresh, revision: 2, japanese: false, locale: Locale(identifier: "en_US"))
        check(updatedSnapshot.dayLookup[today]?.count == 101 && updatedSnapshot.model.total == 106, "A history revision refreshes values without stale snapshots")
        let override = ProgressCalendarModel(period: .month, anchor: today, counts: [today: 20], today: today, calendar: calendar, annualMaximumOverride: 100)
        check(override.annualMaximum == 100 && override.days.first(where: { $0.date == today })?.level == 1, "Month consumes shared annual scale without scanning a year")
        let leap = ProgressCalendarModel(period: .year, anchor: date(2000, 6, 1), counts: [:], today: today, calendar: calendar)
        let leapSnapshot = cache.snapshot(model: leap, revision: 2, japanese: false, locale: Locale(identifier: "en_US"))
        check(leapSnapshot.monthLabels.count == 54 && leapSnapshot.days.count == 366, "The render cache preserves 54-column leap years")
        // Returning to a cached year at another month must not restore its old
        // navigation anchor when the user next moves periods or changes to Month.
        let january = ProgressCalendarModel(period: .year, anchor: date(2026, 1, 1), counts: counts, today: today, calendar: calendar)
        let januarySnapshot = cache.snapshot(model: january, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
        check(januarySnapshot.model.anchor == date(2026, 1, 1), "A cached year's October anchor never overrides January navigation")
        check(calendar.component(.month, from: januarySnapshot.model.shifted(by: -1)) == 1, "Previous year navigation preserves the newly selected January month")
        let januaryBuilds = cache.snapshotBuildCount
        _ = cache.snapshot(model: january, revision: 1, japanese: false, locale: Locale(identifier: "en_US"))
        check(cache.snapshotBuildCount == januaryBuilds, "The corrected year anchor is still cached across repeated reads")
        print("ProgressRenderingChecks: \(checks) passed")
    }
}
