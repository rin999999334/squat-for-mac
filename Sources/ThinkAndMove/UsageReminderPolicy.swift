import Foundation

struct UsageReminderContext {
    var enabled = false
    var eligible = false
    var targetIsFront = false
    var inputQuietTime: TimeInterval?
    var target = 5
}

/// A single source for usage proposals; generation-state detection is not involved.
struct UsageReminderPolicy {
    private(set) var tracker: UsageTimeTracker
    private(set) var presentation: ReminderPresentation?
    private var candidateAt: TimeInterval?
    private var lastTime: TimeInterval?
    var aggregate: UsageAggregate { tracker.aggregate }
    var paused: Bool { tracker.paused }
    var nextDeadline: TimeInterval? { presentation?.expiresAt ?? candidateAt.map { $0 + tracker.configuration.candidateLifetime } }
    init(tracker: UsageTimeTracker) { self.tracker = tracker }

    mutating func receive(_ observation: UsageObservation, context: UsageReminderContext) {
        guard observation.time.isFinite, lastTime.map({ observation.time >= $0 }) ?? true else {
            suspend(); lastTime = nil; return
        }
        lastTime = observation.time
        let oldDay = tracker.aggregate.day
        tracker.observe(observation)
        if oldDay != tracker.aggregate.day { presentation = nil; candidateAt = nil }
        evaluate(time: observation.time, date: observation.date, context: context)
    }
    mutating func evaluate(time: TimeInterval, date: Date, context: UsageReminderContext) {
        guard time.isFinite, context.enabled, !tracker.paused else { presentation = nil; candidateAt = nil; return }
        if let current = presentation {
            if time >= current.expiresAt || !context.eligible || !context.targetIsFront { presentation = nil }
            return
        }
        guard tracker.aggregate.seconds >= tracker.configuration.threshold else { return }
        if candidateAt == nil { candidateAt = time }
        guard let candidateAt else { return }
        if time < candidateAt || time - candidateAt >= tracker.configuration.candidateLifetime {
            self.candidateAt = nil; tracker.consume(at: date, shown: false); return
        }
        guard context.eligible, context.targetIsFront, tracker.cooldownAllows(date),
              let quiet = context.inputQuietTime, quiet.isFinite, quiet >= tracker.configuration.inputQuietTime else { return }
        presentation = ReminderPresentation(id: UUID(), kind: .usage, target: min(30, max(1, context.target)),
                                            shownAt: time, expiresAt: time + tracker.configuration.presentationLifetime)
        tracker.consume(at: date, shown: true); self.candidateAt = nil
    }
    mutating func accept(id: UUID, time: TimeInterval, context: UsageReminderContext) -> ReminderPresentation? {
        guard let current = presentation, current.id == id else { return nil }
        defer { presentation = nil }
        guard time.isFinite, time >= current.shownAt, time < current.expiresAt,
              context.enabled, context.eligible, context.targetIsFront, !tracker.paused else { return nil }
        return current
    }
    mutating func dismiss(id: UUID) { if presentation?.id == id { presentation = nil } }
    mutating func setInterval(_ interval: UsageReminderInterval) { suspend(); tracker.setInterval(interval) }
    mutating func trackerCalendarChanged() { tracker.calendar = .current; suspend() }
    mutating func suspend() { presentation = nil; candidateAt = nil; tracker.resetObservation() }
    mutating func resetForWorkout() { suspend(); tracker.resetTime() }
    mutating func pauseToday(at date: Date) { suspend(); tracker.pauseToday(at: date) }
}
