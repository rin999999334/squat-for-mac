import Foundation

struct ProgressDayPresentation: Identifiable, Equatable {
    let date: Date
    let count: Int
    let future: Bool
    let level: Int
    let accessibilityLabel: String
    let detailLabel: String
    let weekdayLabel: String
    var id: Date { date }
}

struct ProgressRenderSnapshot {
    let model: ProgressCalendarModel
    let days: [ProgressDayPresentation]
    let dayLookup: [Date: ProgressDayPresentation]
    let monthLabels: [String]
    let title: String
    let weeklyMaximum: Int
    let totalText: String
    let summaryText: String
    let maximumText: String
    let japanese: Bool
    let key: String
    func day(at index: Int) -> ProgressDayPresentation? {
        let offset = index - model.leadingCount
        return days.indices.contains(offset) ? days[offset] : nil
    }
}

/// A label snapshot is built only when the history, period anchor, day, time zone or language changes.
/// In particular, pointer movement and selected-date changes never format 365 date labels again.
final class ProgressRenderCache {
    private var snapshots: [String: ProgressRenderSnapshot] = [:]
    private var insertionOrder: [String] = []
    private(set) var snapshotBuildCount = 0
    private(set) var dayLabelBuildCount = 0
    func snapshot(model: ProgressCalendarModel, revision: Int, japanese: Bool, locale: Locale, historyID: ObjectIdentifier? = nil) -> ProgressRenderSnapshot {
        let anchorDay = model.calendar.startOfDay(for: model.anchor)
        let key = "\(String(describing: historyID))|\(revision)|\(model.period.rawValue)|\(anchorDay.timeIntervalSinceReferenceDate)|\(model.start.timeIntervalSinceReferenceDate)|\(model.end.timeIntervalSinceReferenceDate)|\(model.today.timeIntervalSinceReferenceDate)|\(model.calendar.timeZone.identifier)|\(locale.identifier)|\(japanese)|\(model.annualMaximum)"
        if let cached = snapshots[key] { return cached }
        let date = DateFormatter(); date.locale = locale; date.timeZone = model.calendar.timeZone
        date.setLocalizedDateFormatFromTemplate("yyyy MMM d")
        let compactDate = DateFormatter(); compactDate.locale = locale; compactDate.timeZone = model.calendar.timeZone
        compactDate.dateFormat = japanese ? "M月d日" : "MMM d"
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = model.days.map { day in
            let dateLabel = date.string(from: day.date)
            let label = day.future ? (japanese ? "\(dateLabel)、未来" : "\(dateLabel), future") : (japanese ? "\(dateLabel)、\(day.count)回" : "\(dateLabel), \(day.count) \(day.count == 1 ? "repetition" : "repetitions")")
            let compact = compactDate.string(from: day.date)
            let detail = day.future ? "\(compact) · \(japanese ? "未来" : "Future")" : (japanese ? "\(compact) · \(day.count)回" : "\(compact) · \(day.count) \(day.count == 1 ? "rep" : "reps")")
            return ProgressDayPresentation(date: day.date, count: day.count, future: day.future, level: day.level, accessibilityLabel: label, detailLabel: detail, weekdayLabel: weekdays[model.calendar.component(.weekday, from: day.date) - 1])
        }
        let month = DateFormatter(); month.locale = locale; month.timeZone = model.calendar.timeZone
        month.dateFormat = japanese ? "M月" : "MMM"
        var monthLabels = [String](repeating: "", count: model.weekColumns)
        for (offset, day) in model.days.enumerated() where model.calendar.component(.day, from: day.date) == 1 {
            monthLabels[(model.leadingCount + offset) / 7] = month.string(from: day.date)
        }
        let title: String
        switch model.period {
        case .year: date.dateFormat = "yyyy"; title = date.string(from: model.anchor)
        case .month: date.locale = Locale(identifier: "en_US_POSIX"); date.dateFormat = "MMMM yyyy"; title = date.string(from: model.anchor)
        case .week: date.dateFormat = "M/d"; title = "\(date.string(from: model.start))–\(date.string(from: model.end))"
        }
        let number = NumberFormatter(); number.locale = locale; number.numberStyle = .decimal
        let year = model.calendar.component(.year, from: model.anchor)
        let snapshot = ProgressRenderSnapshot(model: model, days: days, dayLookup: Dictionary(uniqueKeysWithValues: days.map { ($0.date, $0) }), monthLabels: monthLabels, title: title,
            weeklyMaximum: max(1, days.filter { !$0.future }.map(\.count).max() ?? 1), totalText: number.string(from: NSNumber(value: model.total)) ?? "\(model.total)",
            summaryText: japanese ? "回・\(model.activeDays)日" : "reps · \(model.activeDays) active days",
            maximumText: japanese ? "\(year)年の最大 \(model.annualMaximum)回を基準" : "\(year) max: \(model.annualMaximum) reps", japanese: japanese, key: key)
        snapshots[key] = snapshot; insertionOrder.append(key)
        while insertionOrder.count > 12 { snapshots.removeValue(forKey: insertionOrder.removeFirst()) }
        snapshotBuildCount += 1; dayLabelBuildCount += days.count
        return snapshot
    }
}
