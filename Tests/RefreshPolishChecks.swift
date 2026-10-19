import Foundation
import SwiftUI

@main enum RefreshPolishChecks {
    @MainActor static func main() async throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { if !value() { FileHandle.standardError.write(Data(("FAIL: " + message + "\n").utf8)); fatalError(message) }; checks += 1 }
        func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.000001 }
        let timing = RefreshNoticeTimeline(expiresAt: 110, countdown: true)
        check(timing.phase(at: 100) == .counting && timing.remaining(at: 100) == 10, "Countdown begins at 10")
        check(timing.phase(at: 109.999) == .counting, "Counting continues until deadline")
        check(timing.phase(at: 110) == .holdingZero && timing.remaining(at: 110) == 0, "Zero begins exactly at deadline")
        check(timing.phase(at: 110.399) == .holdingZero && timing.opacity(at: 110.399) == 1, "Zero is fully visible throughout hold")
        check(timing.phase(at: 110.4) == .fading && timing.opacity(at: 110.4) == 1, "Fade starts after 0.4 seconds")
        check(timing.phase(at: 110.52) == .fading && near(timing.opacity(at: 110.52), 0.125), "Fade has a continuous eased midpoint")
        check(timing.phase(at: 110.639) == .fading && timing.opacity(at: 110.639) < 0.000001, "Panel survives until opacity is almost zero")
        check(timing.phase(at: timing.closesAt) == .closed && timing.opacity(at: timing.closesAt) == 0, "Only fade completion closes the panel")
        check(near(timing.closesAt, 110.64), "Total extra lifetime is 0.64 seconds")
        check(timing.phase(at: 200) == .closed && timing.remaining(at: 200) == 0, "A stalled clock cannot yield negative digits or reopen")
        let primary = RefreshNoticeTimeline(expiresAt: 108, countdown: false)
        check(primary.phase(at: 108) == .fading && near(primary.closesAt, 108.18), "Primary notification keeps its existing lifetime")
        let item = RefreshInvitation(id: UUID(), style: .countdown, target: 30, source: "ChatGPT/Codex", seconds: 0, shownAt: 100, expiresAt: 110, isTest: true)
        let lifetime = RefreshNotificationLifetime(item: item, now: 100)
        lifetime.advance(to: 110.2)
        check(lifetime.timeline.phase(at: lifetime.now) == .holdingZero, "Lifetime publishes the same zero hold used to render")
        lifetime.advance(to: timing.closesAt); lifetime.advance(to: 109)
        check(lifetime.now == timing.closesAt, "Closed clock ignores stale ticks")
        check(RefreshIntervalGeometry.values.last == 180, "Reminder max remains 180")
        let maxCenter = RefreshIntervalGeometry.points.last!
        check(maxCenter + 7.5 == 363, "Maximum knob touches track endpoint")
        check(RefreshIntervalGeometry.fillWidth(at: maxCenter) == 268, "Maximum fills the entire track")
        check(RefreshIntervalGeometry.fillWidth(at: 284.5) == 197, "120-minute reference calibration is preserved")
        check(RefreshIntervalGeometry.fillWidth(at: 1000) == 268 && RefreshIntervalGeometry.fillWidth(at: -10) == 0, "Fill cannot overflow")
        let providers: Set<String> = [AIProvider.chatgptDesktop.rawValue, AIProvider.claudeDesktop.rawValue]
        check(RefreshUsageTotals(days: [], selected: providers) == .init(days: [.init()], selected: providers), "No measurement remains unknown")
        var chat = RefreshDayUsage(); chat.ai[AIProvider.chatgptDesktop.rawValue] = 1800; chat.measuredAI = [AIProvider.chatgptDesktop.rawValue]; chat.desk = 3600; chat.measuredDesk = true
        var claude = RefreshDayUsage(); claude.ai[AIProvider.claudeDesktop.rawValue] = 3600; claude.measuredAI = [AIProvider.claudeDesktop.rawValue]; claude.desk = 7200; claude.measuredDesk = true
        let total = RefreshUsageTotals(days: [chat,claude], selected: providers)
        check(total.ai == "01h30m" && total.desk == "03h00m", "All-time totals aggregate across days and both providers")
        let single = RefreshUsageTotals(days: [chat,claude], selected: [AIProvider.chatgptDesktop.rawValue])
        check(single.ai == "00h30m" && single.desk == "03h00m", "AI choice does not filter Desk time")
        var zero = RefreshDayUsage(); zero.measuredAI = [AIProvider.chatgptDesktop.rawValue]; zero.measuredDesk = true
        let measuredZero = RefreshUsageTotals(days: [zero], selected: providers)
        check(measuredZero.ai == "00h00m" && measuredZero.desk == "00h00m", "Measured zero differs from missing data")
        let noSelection = RefreshUsageTotals(days: [chat], selected: [])
        check(noSelection.ai == "--h--m" && noSelection.desk == "01h00m", "No selected AI remains unknown")
        let presentation = RefreshPresentation()
        var finishResize: (() -> Void)?
        presentation.show(.history, animated: true) { finishResize = $0 }
        check(presentation.screen == .home && presentation.isTransitioning && presentation.opacity == 0, "Old content fades before resize")
        try await Task.sleep(nanoseconds: 120_000_000)
        check(presentation.screen == .history && presentation.opacity == 0 && finishResize != nil, "New content remains hidden while resize is pending")
        finishResize?()
        check(presentation.opacity == 1, "Only native resize completion reveals new content")
        try await Task.sleep(nanoseconds: 180_000_000)
        check(!presentation.isTransitioning, "Interaction returns after reveal")
        presentation.show(.home, animated: true) { _ in fatalError("Cancelled transition must not resize") }
        presentation.show(.settings, animated: false) { $0() }
        try await Task.sleep(nanoseconds: 120_000_000)
        check(presentation.screen == .settings && presentation.opacity == 1 && !presentation.isTransitioning, "A newer navigation cancels stale work")
        var staleCompletion: (() -> Void)?
        presentation.show(.history, animated: true) { staleCompletion = $0 }
        try await Task.sleep(nanoseconds: 120_000_000)
        presentation.show(.workout, animated: false) { $0() }
        staleCompletion?()
        check(presentation.screen == .workout && !presentation.isTransitioning && presentation.opacity == 1, "Late resize cannot resurrect an old screen")
        print("PASS: \(checks) UI polish behavior checks")
    }
}
