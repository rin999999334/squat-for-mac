import Foundation
import Combine

/// Period, anchor and focus change together, producing one view invalidation.
@MainActor final class ProgressSelection: ObservableObject {
    struct State: Equatable {
        var period: ProgressPeriod
        var anchor: Date
        var selectedDate: Date
    }
    @Published private(set) var state: State
    init(now: Date = Date()) {
        state = State(period: .week, anchor: now, selectedDate: ProgressCalendarModel.localCalendar().startOfDay(for: now))
    }
    var period: ProgressPeriod { state.period }
    var anchor: Date { state.anchor }
    var selectedDate: Date { state.selectedDate }
    func update(period: ProgressPeriod? = nil, anchor: Date? = nil, selectedDate: Date? = nil) {
        let next = State(period: period ?? state.period, anchor: anchor ?? state.anchor, selectedDate: selectedDate ?? state.selectedDate)
        if state != next { state = next }
    }
    func reset(now: Date = Date()) {
        update(period: .week, anchor: now, selectedDate: ProgressCalendarModel.localCalendar().startOfDay(for: now))
    }
}
