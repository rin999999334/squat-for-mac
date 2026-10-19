import Foundation

@main enum RefreshMenuUsageChecks {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        let missing = RefreshMenuUsageSnapshot()
        check(missing.chatgptDisplay == "--h--m--s" && missing.claudeDisplay == "--h--m--s", "Unmeasured providers stay distinct from measured zero")
        let separate = RefreshMenuUsageSnapshot(chatgptSeconds: 623.9, claudeSeconds: 1234.9, deskSeconds: 1950.1,
                                               elapsedSeconds: 1798.4, thresholdSeconds: 1800)
        check(separate.chatgptDisplay == "00h10m23s", "ChatGPT/Codex displays only its own total")
        check(separate.claudeDisplay == "00h20m34s", "Claude displays only its own total")
        check(separate.deskDisplay == "00h32m30s", "PC total remains independently formatted")
        check(separate.remainingDisplay == "00m 02s", "Fractional seconds round remaining time upward")
        let next = RefreshMenuUsageSnapshot(chatgptSeconds: 624.9, claudeSeconds: 1234.9,
                                           elapsedSeconds: 1799.4, thresholdSeconds: 1800)
        check(next.remainingDisplay == "00m 01s", "Remaining time updates within a minute")
        check(next != separate, "Sub-minute usage changes invalidate the menu snapshot")
        check(next.fraction > separate.fraction && next.fraction < 1, "Progress advances before the next minute boundary")
        let reached = RefreshMenuUsageSnapshot(chatgptSeconds: 0, elapsedSeconds: 1800, thresholdSeconds: 1800)
        check(reached.chatgptDisplay == "00h00m00s", "Measured zero is shown as a real measurement")
        check(reached.remainingSeconds == 0 && reached.fraction == 1, "Reached threshold displays zero and a full progress bar")
        let exceeded = RefreshMenuUsageSnapshot(elapsedSeconds: 1900, thresholdSeconds: 1800)
        check(exceeded.remainingSeconds == 0 && exceeded.fraction == 1, "Overdue reminder never displays a negative remaining time")
        let longInterval = RefreshMenuUsageSnapshot(elapsedSeconds: 1, thresholdSeconds: 10800)
        check(longInterval.remainingDisplay == "179m 59s", "Maximum configured interval remains accurate")
        let invalid = RefreshMenuUsageSnapshot(chatgptSeconds: .infinity, claudeSeconds: -.infinity, deskSeconds: -1,
                                              elapsedSeconds: .nan, thresholdSeconds: .infinity)
        check(invalid.chatgptSeconds == 0 && invalid.claudeSeconds == 0 && invalid.deskSeconds == 0, "Malformed display values are safe")
        check(invalid.remainingSeconds == 3600 && invalid.fraction == 0, "Invalid reminder values have a finite fallback")
        print("PASS: \(count) menu usage checks")
    }
}
