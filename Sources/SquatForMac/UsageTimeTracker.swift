import Foundation

struct UsageObservation {
    let time: TimeInterval
    let date: Date
    let targetIsFront: Bool
    let systemActive: Bool
    let idleSeconds: TimeInterval?
}

struct UsageReminderConfiguration {
    var threshold: TimeInterval = 3_600
    var idleLimit: TimeInterval = 300
    var maximumSampleGap: TimeInterval = 5
    var inputQuietTime: TimeInterval = 3
    var candidateLifetime: TimeInterval = 300
    var presentationLifetime: TimeInterval = 8
    var minimumNoticeInterval: TimeInterval = 3_600

    init(interval: UsageReminderInterval = .minutes60) {
        threshold = interval.seconds
        minimumNoticeInterval = interval.seconds
    }
}

struct UsageAggregate: Codable, Equatable {
    var provider: String
    var day: Date
    var seconds: TimeInterval = 0
    var lastNotice: Date?
    var pausedDay: Date?
}

struct UsageProgress: Equatable {
    let elapsedMinutes: Int
    let targetMinutes: Int
    init(seconds: TimeInterval = 0, threshold: TimeInterval = 3600) {
        let limit = threshold.isFinite && threshold > 0 ? threshold : 3600
        elapsedMinutes = Int(min(limit, max(0, seconds.isFinite ? seconds : 0)) / 60)
        targetMinutes = max(1, Int(limit / 60))
    }
}

/// Only aggregate time is retained. No application timelines or input contents.
struct UsageTimeTracker {
    private(set) var aggregate: UsageAggregate
    private var previous: UsageObservation?
    private(set) var configuration: UsageReminderConfiguration
    var calendar: Calendar
    init(provider: String, date: Date, saved: UsageAggregate? = nil,
         configuration: UsageReminderConfiguration = .init(), calendar: Calendar = .current) {
        self.configuration = configuration; self.calendar = calendar
        let day = calendar.startOfDay(for: date)
        if let saved, saved.provider == provider, saved.day == day {
            aggregate = saved
            aggregate.seconds = saved.seconds.isFinite && saved.seconds < configuration.threshold ? max(0, saved.seconds) : 0
            if let notice = aggregate.lastNotice, notice > date { aggregate.lastNotice = date }
        } else {
            aggregate = UsageAggregate(provider: provider, day: day, lastNotice: saved?.lastNotice)
        }
    }
    var paused: Bool { aggregate.pausedDay == aggregate.day }
    mutating func observe(_ observation: UsageObservation) {
        guard observation.time.isFinite, observation.date.timeIntervalSinceReferenceDate.isFinite else { previous = nil; return }
        let day = calendar.startOfDay(for: observation.date)
        if aggregate.day != day {
            aggregate.day = day; aggregate.seconds = 0; aggregate.pausedDay = nil; previous = nil
        }
        if let notice = aggregate.lastNotice, notice > observation.date { aggregate.lastNotice = observation.date }
        defer { previous = observation }
        guard !paused, observation.targetIsFront, observation.systemActive,
              let previous, previous.targetIsFront, previous.systemActive,
              let idle = observation.idleSeconds, idle.isFinite, idle >= 0 else { return }
        let interval = observation.time - previous.time
        guard interval > 0, interval <= configuration.maximumSampleGap else { return }
        // A final sample can straddle the point at which reading becomes idle.
        let activeEnd = min(observation.time, observation.time - idle + configuration.idleLimit)
        let delta = max(0, activeEnd - previous.time)
        aggregate.seconds = min(configuration.threshold, aggregate.seconds + delta)
    }
    mutating func consume(at date: Date, shown: Bool) {
        aggregate.seconds = 0
        if shown { aggregate.lastNotice = date }
    }
    mutating func pauseToday(at date: Date) {
        aggregate.day = calendar.startOfDay(for: date); aggregate.pausedDay = aggregate.day
        aggregate.seconds = 0; previous = nil
    }
    mutating func resetObservation() { previous = nil }
    mutating func setInterval(_ interval: UsageReminderInterval) {
        configuration.threshold = interval.seconds
        configuration.minimumNoticeInterval = interval.seconds
        aggregate.seconds = min(aggregate.seconds, interval.seconds)
        previous = nil
    }
    mutating func resetTime() { aggregate.seconds = 0; previous = nil }
    func cooldownAllows(_ date: Date) -> Bool {
        aggregate.lastNotice.map { date.timeIntervalSince($0) >= configuration.minimumNoticeInterval } ?? true
    }
}
