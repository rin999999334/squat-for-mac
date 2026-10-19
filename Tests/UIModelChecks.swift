import Foundation
import CoreGraphics
import Combine

@main
struct UIModelChecks {
    @MainActor static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }; checks += 1
        }
        let center = CGPoint(x: 125, y: 125)
        for goal in 1...30 {
            let point = GoalRingModel.point(for: goal)
            check(GoalRingModel.value(at: point).value == goal, "Ring point round-trip for \(goal)")
        }
        let start = GoalRingModel.point(for: 1)
        let end = GoalRingModel.point(for: 30)
        check(start.x < center.x && start.y > center.y, "Start is lower-left")
        check(end.x > center.x && end.y > center.y, "End is lower-right")
        check(GoalRingModel.value(at: CGPoint(x: 125, y: 15)).value == 16, "Top is midpoint")
        check(GoalRingModel.value(at: CGPoint(x: 190, y: 210)).value >= 29, "Gap near max clamps max")
        check(GoalRingModel.value(at: CGPoint(x: 60, y: 210)).value == 1, "Gap near min clamps min")
        let acrossGap = GoalRingModel.value(at: GoalRingModel.point(for: 1), previousAngle: 405)
        check(acrossGap.value == 30 && acrossGap.angle > 405, "Dragging past max never wraps to min")
        let stillBeyond = GoalRingModel.value(at: GoalRingModel.point(for: 8), previousAngle: acrossGap.angle)
        check(stillBeyond.value == 30, "Unwrapped drag remains clamped past gap")
        let reverse = GoalRingModel.value(at: GoalRingModel.point(for: 29), previousAngle: 405)
        check(reverse.value == 29, "Reverse from max tracks smoothly")
        check(GoalRingModel.value(at: end, previousAngle: 135).value == 1, "Dragging past min never wraps to max")

        let calendar = ProgressCalendarModel.localCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date { calendar.date(from: DateComponents(year: year, month: month, day: day))! }
        let maxCounts = [0, 1, 4, 5, 8, 9, 12, 13, 16, 17, 20]
        let levels = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5]
        for (count, level) in zip(maxCounts, levels) { check(ProgressCalendarModel.level(count: count, maximum: 20) == level, "Relative level \(count)") }
        let leap = ProgressCalendarModel(period: .month, anchor: date(2024, 2, 14), counts: [:], today: date(2026, 10, 15), calendar: calendar)
        check(leap.days.count == 29, "Leap February has 29 cells")
        check(leap.leadingCount == 4, "February 2024 starts Thursday")
        let october = ProgressCalendarModel(period: .month, anchor: date(2025, 10, 15), counts: [:], today: date(2026, 10, 15), calendar: calendar)
        check(october.clampedSelection(date(2025, 1, 1)) == date(2025, 10, 1), "Switching Year to Month clamps prior selection into displayed month")
        check(october.movedSelection(october.clampedSelection(date(2025, 1, 1)), horizontal: 1) == date(2025, 10, 2), "Arrow navigation stays in displayed month after switching period")
        let longYear = ProgressCalendarModel(period: .year, anchor: date(2000, 6, 1), counts: [:], today: date(2026, 10, 15), calendar: calendar)
        check(longYear.weekColumns == 54 && longYear.days.count == 366, "Saturday leap year has 54 weeks")
        let dst = ProgressCalendarModel(period: .month, anchor: date(2026, 3, 1), counts: [:], today: date(2026, 10, 15), calendar: calendar)
        check(dst.days.count == 31 && Set(dst.days.map(\.date)).count == 31, "DST does not duplicate or omit days")
        check(dst.days[8].date.timeIntervalSince(dst.days[7].date) == 23 * 3600, "DST follows calendar midnight")
        let crossYear = ProgressCalendarModel(period: .week, anchor: date(2026, 1, 1), counts: [date(2025, 12, 31): 1000, date(2026, 1, 1): 5], today: date(2026, 1, 1), calendar: calendar)
        check(crossYear.total == 1005, "Week includes both years")
        check(crossYear.annualMaximum == 5, "Relative maximum stays in selected year")
        check(crossYear.start == date(2025, 12, 28), "Week begins Sunday")
        check(crossYear.days.filter(\.future).count == 2 && !crossYear.canAdvance, "Future days remain unavailable")
        check(crossYear.movedSelection(date(2026, 1, 1), horizontal: 1) == date(2026, 1, 1), "Selection cannot enter future")
        let unlimited = ProgressCalendarModel(period: .year, anchor: date(2025, 1, 1), counts: [date(2025, 1, 1): 12345], today: date(2026, 1, 1), calendar: calendar)
        check(unlimited.total == 12345 && unlimited.annualMaximum == 12345, "Counts have no daily cap")
        check(unlimited.movedSelection(date(2025, 1, 1), horizontal: 1) == date(2025, 1, 8), "Year horizontal keys move 7 days")
        let fit = CameraViewport(size: CGSize(width: 300, height: 400), aspect: 4.0 / 3.0, contentMode: .fit)
        check(fit.imageRect == CGRect(x: 0, y: 87.5, width: 300, height: 225), "Fit preserves full frame and centered bars")
        check(fit.point(x: 0, y: 1) == fit.imageRect.origin, "Fit points use same top-left image origin")
        let fill = CameraViewport(size: CGSize(width: 300, height: 400), aspect: 4.0 / 3.0)
        check(fill.imageRect.width > 300 && fill.imageRect.height == 400, "Existing fill default remains unchanged")
        let selection = ProgressSelection(now: date(2026, 10, 15))
        var changes = 0
        let observation = selection.$state.dropFirst().sink { _ in changes += 1 }
        selection.update(period: .month, anchor: date(2026, 9, 1), selectedDate: date(2026, 9, 10))
        check(changes == 1 && selection.period == .month && selection.selectedDate == date(2026, 9, 10), "Period, anchor and selection publish once atomically")
        selection.update(period: .month)
        check(changes == 1, "Identical selection never invalidates the chart")
        withExtendedLifetime(observation) {}
        print("UIModelChecks: \(checks) passed")
    }
}
