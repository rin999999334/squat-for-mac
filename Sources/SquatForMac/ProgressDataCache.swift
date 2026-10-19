import Foundation
import Combine

/// Immutable calendar projections, invalidated by real count/calendar changes only.
/// Diagnostics are deliberately not published: a cache lookup during body must not trigger another body.
@MainActor
final class ProgressDataCache: ObservableObject {
    private(set) var modelBuildCount = 0
    private(set) var yearBuildCount = 0

    private struct Epoch: Equatable {
        let history: ObjectIdentifier
        let revision: Int
        let calendar: String
        let timeZone: String
        let today: Date
    }
    private struct ModelKey: Hashable {
        let period: String
        let start: Date
        let end: Date
        let anchor: Date
    }
    private struct YearSnapshot {
        let counts: [Date: Int]
        let maximum: Int
    }

    private var epoch: Epoch?
    private var models: [ModelKey: ProgressCalendarModel] = [:]
    private var years: [Int: YearSnapshot] = [:]

    func model(history: WorkoutHistory, period: ProgressPeriod, anchor: Date,
               today: Date = Date(), calendar suppliedCalendar: Calendar? = nil) -> ProgressCalendarModel {
        let calendar = suppliedCalendar ?? ProgressCalendarModel.localCalendar(timeZone: history.calendarTimeZone)
        let todayBoundary = calendar.startOfDay(for: today)
        let currentEpoch = Epoch(history: ObjectIdentifier(history), revision: history.historyRevision,
                                 calendar: String(describing: calendar.identifier), timeZone: calendar.timeZone.identifier,
                                 today: todayBoundary)
        if epoch != currentEpoch {
            epoch = currentEpoch
            models.removeAll(keepingCapacity: true)
            years.removeAll(keepingCapacity: true)
        }
        let bounds = ProgressCalendarModel.bounds(period: period, anchor: anchor, calendar: calendar)
        let key = ModelKey(period: period.rawValue, start: bounds.0, end: bounds.1,
                           anchor: calendar.startOfDay(for: anchor))
        if let cached = models[key] { return cached }

        let year = calendar.component(.year, from: anchor)
        let annual: YearSnapshot
        if let cached = years[year] { annual = cached }
        else {
            let yearBounds = ProgressCalendarModel.bounds(period: .year, anchor: anchor, calendar: calendar)
            let values = history.dayCounts(from: yearBounds.0, through: yearBounds.1)
            annual = YearSnapshot(counts: Dictionary(uniqueKeysWithValues: values.map { ($0.date, $0.count) }),
                                  maximum: values.lazy.filter { $0.date <= todayBoundary }.map(\.count).max() ?? 0)
            if years.count >= 8, let oldest = years.keys.first { years.removeValue(forKey: oldest) }
            years[year] = annual; yearBuildCount += 1
        }
        // Cross-year weeks need both years' counts, while their colors use the
        // selected year's scale. This is an indexed seven-day lookup, not an event scan.
        let counts = period == .week
            ? Dictionary(uniqueKeysWithValues: history.dayCounts(from: bounds.0, through: bounds.1).map { ($0.date, $0.count) })
            : annual.counts
        let maximum = annual.maximum
        let result = ProgressCalendarModel(period: period, anchor: anchor, counts: counts,
                                           today: todayBoundary, calendar: calendar, annualMaximumOverride: maximum)
        if models.count >= 64 { models.removeAll(keepingCapacity: true) }
        models[key] = result
        modelBuildCount += 1
        return result
    }
}
