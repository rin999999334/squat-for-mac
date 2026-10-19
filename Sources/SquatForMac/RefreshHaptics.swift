import AppKit

@MainActor enum RefreshHaptics {
    private static var last: [String: Double] = [:]
    static func changed(from old: Int, to new: Int, channel: String, enabled: Bool = true) {
        guard enabled, old != new, channel != "volume" || old/5 != new/5 else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (last[channel] ?? -.infinity) >= 0.05 else { return }
        last[channel] = now
        NSHapticFeedbackManager.defaultPerformer.perform(channel == "volume" ? .levelChange : .alignment, performanceTime: .now)
    }
}
