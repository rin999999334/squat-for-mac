import Foundation
import Combine

/// One monotonic timeline drives digits, opacity, and the final close callback.
struct RefreshNoticeTimeline {
    enum Phase: Equatable { case counting, holdingZero, fading, closed }
    let expiresAt: Double
    let countdown: Bool
    static let zeroHold = 0.4
    static let countdownFade = 0.24
    var fadeDuration: Double { countdown ? Self.countdownFade : 0.18 }
    var fadeStartsAt: Double { expiresAt + (countdown ? Self.zeroHold : 0) }
    var closesAt: Double { fadeStartsAt + fadeDuration }
    func phase(at now: Double) -> Phase {
        if now < expiresAt { return .counting }
        if now < fadeStartsAt { return .holdingZero }
        return now < closesAt ? .fading : .closed
    }
    func remaining(at now: Double) -> Double { max(0, expiresAt - now) }
    func opacity(at now: Double) -> Double {
        if now >= closesAt { return 0 }
        if now <= fadeStartsAt { return 1 }
        let progress = min(1, max(0, (now - fadeStartsAt) / fadeDuration))
        return pow(1 - progress, 3)
    }
}

@MainActor final class RefreshNotificationLifetime: ObservableObject {
    let timeline: RefreshNoticeTimeline
    @Published private(set) var now: Double
    private var timer: Timer?
    private var onClosed: (() -> Void)?
    private var finished = false
    init(item: RefreshInvitation, now: Double = ProcessInfo.processInfo.systemUptime) {
        timeline = .init(expiresAt: item.expiresAt, countdown: item.style == .countdown)
        self.now = now
    }
    func start(onClosed: @escaping () -> Void) {
        stop(); finished = false; self.onClosed = onClosed
        let timer = Timer(timeInterval: 1/30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance(to: ProcessInfo.processInfo.systemUptime) }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        advance(to: ProcessInfo.processInfo.systemUptime)
    }
    func advance(to now: Double) {
        guard !finished else { return }
        self.now = now
        if timeline.phase(at: now) == .closed {
            finished = true
            let completion = onClosed
            stop()
            completion?()
        }
    }
    func stop() { timer?.invalidate(); timer = nil; onClosed = nil }
}

enum RefreshIntervalGeometry {
    static let left: CGFloat = 95
    static let width: CGFloat = 268
    static let points: [CGFloat] = [134, 183, 232, 284.5, 355.5]
    static let values = [30, 60, 90, 120, 180]
    static func fillWidth(at center: CGFloat) -> CGFloat { min(width, max(0, center - left + 7.5)) }
}

struct RefreshUsageTotals: Equatable {
    let ai: String
    let desk: String
    init(days: [RefreshDayUsage], selected: Set<String>) {
        let aiKnown = days.contains { !$0.measuredAI.isDisjoint(with: selected) }
        let deskKnown = days.contains { $0.measuredDesk }
        ai = aiKnown ? RefreshGeometry.duration(days.reduce(0) { sum, day in sum + selected.reduce(0) { $0 + max(0, day.ai[$1] ?? 0) } }) : "--h--m"
        desk = deskKnown ? RefreshGeometry.duration(days.reduce(0) { $0 + max(0, $1.desk) }) : "--h--m"
    }
}
