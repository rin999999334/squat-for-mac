import Foundation

/// One ordinary invitation and at most one follow-up. The host supplies a continuous clock.
struct RefreshReminderCycle {
    private(set) var followupDeadline: Double?
    var pending: Bool { followupDeadline != nil }
    func candidate(now: Double, regularReady: Bool) -> RefreshNotificationStyle? {
        if let deadline = followupDeadline {
            return regularReady || now >= deadline ? .countdown : nil
        }
        return regularReady ? .primary : nil
    }
    mutating func displayed(_ style: RefreshNotificationStyle, at now: Double) {
        followupDeadline = style == .primary ? now + 2700 : nil
    }
    mutating func cancel() { followupDeadline = nil }
}
