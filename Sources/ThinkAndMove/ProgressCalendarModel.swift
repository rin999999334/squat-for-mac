import Foundation

// Calendar-day arithmetic keeps midnight and DST boundaries aligned with the Mac's time zone.
enum ProgressPeriod: String, CaseIterable, Identifiable {
    case week, month, year
    var id: String { rawValue }
}

struct ProgressCalendarModel {
    struct Day: Identifiable {
        let date: Date
        let count: Int
        let future: Bool
        let level: Int
        var id: Date { date }
    }
    let calendar: Calendar
    let period: ProgressPeriod
    let anchor: Date
    let today: Date
    let start: Date
    let end: Date
    let days: [Day]
    let annualMaximum: Int
    var total: Int { days.filter { !$0.future }.reduce(0) { $0 + $1.count } }
    var activeDays: Int { days.filter { !$0.future && $0.count > 0 }.count }
    var leadingCount: Int { (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7 }
    var weekColumns: Int { (leadingCount + days.count + 6) / 7 }
    var canAdvance: Bool { end < today }

    static func localCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }
    static func bounds(period: ProgressPeriod, anchor: Date, calendar: Calendar = localCalendar()) -> (Date, Date) {
        let component: Calendar.Component = period == .week ? .weekOfYear : period == .month ? .month : .year
        let interval = calendar.dateInterval(of: component, for: anchor)!
        return (calendar.startOfDay(for: interval.start), calendar.date(byAdding: .day, value: -1, to: interval.end)!)
    }
    init(period: ProgressPeriod, anchor: Date, counts: [Date: Int], today: Date = Date(), calendar: Calendar = localCalendar(), annualMaximumOverride: Int? = nil) {
        self.calendar = calendar; self.period = period; self.anchor = anchor
        let todayBoundary = calendar.startOfDay(for: today)
        self.today = todayBoundary
        (start, end) = Self.bounds(period: period, anchor: anchor, calendar: calendar)
        let year = calendar.component(.year, from: anchor)
        annualMaximum = annualMaximumOverride ?? counts.filter { calendar.component(.year, from: $0.key) == year && $0.key <= todayBoundary }.map(\.value).max() ?? 0
        let maximum = annualMaximum
        var built: [Day] = []
        var date = start
        while date <= end {
            let count = max(0, counts[date, default: 0])
            built.append(Day(date: date, count: count, future: date > self.today, level: Self.level(count: count, maximum: maximum)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date), next > date else { break }
            date = next
        }
        days = built
    }
    static func level(count: Int, maximum: Int) -> Int {
        count > 0 ? min(5, max(1, Int(ceil(5 * Double(count) / Double(max(1, maximum)))))) : 0
    }
    func day(at index: Int) -> Day? {
        let offset = index - leadingCount
        return days.indices.contains(offset) ? days[offset] : nil
    }
    func clampedSelection(_ date: Date) -> Date {
        min(today, min(end, max(start, date)))
    }
    func shifted(by amount: Int) -> Date {
        calendar.date(byAdding: period == .week ? .weekOfYear : period == .month ? .month : .year, value: amount, to: anchor) ?? anchor
    }
    func movedSelection(_ current: Date, horizontal: Int = 0, vertical: Int = 0) -> Date {
        let offset = period == .year ? horizontal * 7 + vertical : horizontal + vertical * 7
        return min(today, calendar.date(byAdding: .day, value: offset, to: current) ?? current)
    }
}
