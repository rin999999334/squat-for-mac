import Foundation

/// A display-only snapshot. Reminder decisions keep their original precise ledger values.
struct RefreshMenuUsageSnapshot: Equatable {
    let chatgptSeconds: Int?
    let claudeSeconds: Int?
    let deskSeconds: Int?
    let elapsedSeconds: Int
    let targetSeconds: Int
    let remainingSeconds: Int

    init(chatgptSeconds: Double? = nil, claudeSeconds: Double? = nil, deskSeconds: Double? = nil,
         elapsedSeconds: Double = 0, thresholdSeconds: Double = 3600) {
        self.chatgptSeconds = chatgptSeconds.map(Self.wholeSeconds)
        self.claudeSeconds = claudeSeconds.map(Self.wholeSeconds)
        self.deskSeconds = deskSeconds.map(Self.wholeSeconds)
        let target = thresholdSeconds.isFinite && thresholdSeconds > 0 ? min(thresholdSeconds, Self.maximumSeconds) : 3600
        let elapsed = min(target, max(0, elapsedSeconds.isFinite ? elapsedSeconds : 0))
        self.elapsedSeconds = Int(elapsed)
        targetSeconds = max(1, Int(ceil(target)))
        // Round remaining time upwards so 00m 00s never appears before the threshold.
        remainingSeconds = Int(ceil(target - elapsed))
    }
    var chatgptDisplay: String { Self.duration(chatgptSeconds) }
    var claudeDisplay: String { Self.duration(claudeSeconds) }
    var deskDisplay: String { Self.duration(deskSeconds) }
    var remainingDisplay: String { String(format: "%02dm %02ds", remainingSeconds / 60, remainingSeconds % 60) }
    var fraction: Double { min(1, max(0, Double(elapsedSeconds) / Double(targetSeconds))) }
    private static let maximumSeconds: Double = 3_600_000_000
    private static func wholeSeconds(_ seconds: Double) -> Int {
        Int(max(0, seconds.isFinite ? min(seconds, maximumSeconds) : 0))
    }
    private static func duration(_ seconds: Int?) -> String {
        guard let seconds else { return "--h--m--s" }
        return String(format: "%02dh%02dm%02ds", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
