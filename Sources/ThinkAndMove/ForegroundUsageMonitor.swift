import AppKit
import Combine
import CoreGraphics

@MainActor final class ForegroundUsageMonitor: ObservableObject {
    enum Status: Equatable { case off, unavailable, waiting, tracking, idle, idleUnavailable, paused, suspended }
    @Published private(set) var status: Status = .off
    @Published private(set) var progress = UsageProgress()
    private(set) var targetIsFront = false
    private(set) var enabled = false
    private var provider: AIProvider = .chatgptDesktop
    private var suspended = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var applicationIDs = Set<String>()
    private var paused = false
    var onObservation: ((UsageObservation) -> Void)?
    var onPauseToday: (() -> Void)?
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(discover: name != NSWorkspace.didActivateApplicationNotification) }
            })
        }
    }
    deinit { timer?.invalidate(); observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver) }
    func configure(enabled: Bool, provider: AIProvider, paused: Bool = false) {
        self.enabled = enabled; self.provider = provider; self.paused = paused
        refresh()
    }
    func suspend() { suspended = true; targetIsFront = false; timer?.invalidate(); timer = nil; if enabled { setStatus(.suspended) }; sample() }
    func resume() { suspended = false; refresh() }
    func stop() { enabled = false; suspended = false; targetIsFront = false; timer?.invalidate(); timer = nil; setStatus(.off) }
    func pauseToday() { onPauseToday?(); paused = true; refresh() }
    func refresh(discover: Bool = true) {
        let workspace = NSWorkspace.shared
        let candidates = provider == .chatgptDesktop ? ["com.openai.chat", "com.openai.codex"] : ["com.anthropic.claudefordesktop"]
        if discover { applicationIDs = Set(candidates.filter { id in
            workspace.urlForApplication(withBundleIdentifier: id) != nil || NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { !$0.isTerminated }
        }) }
        targetIsFront = enabled && !suspended && applicationIDs.contains(workspace.frontmostApplication?.bundleIdentifier ?? "")
        timer?.invalidate(); timer = nil
        if !enabled { setStatus(.off) }
        else if paused { setStatus(.paused) }
        else if suspended { setStatus(.suspended) }
        else if applicationIDs.isEmpty { setStatus(.unavailable) }
        else { setStatus(targetIsFront ? .tracking : .waiting) }
        sample()
        if enabled && targetIsFront && !suspended && !paused {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sample() }
            }
            timer.tolerance = 0.25
            RunLoop.main.add(timer, forMode: .common); self.timer = timer
        }
    }
    func observation() -> UsageObservation {
        UsageObservation(time: ProcessInfo.processInfo.systemUptime, date: Date(), targetIsFront: targetIsFront,
                         systemActive: enabled && !suspended, idleSeconds: Self.quietTime(includeMovement: true))
    }
    private func sample() {
        guard enabled else { return }
        let value = observation()
        if !paused && targetIsFront {
            if let idle = value.idleSeconds, idle.isFinite, idle >= 0 { setStatus(idle >= 300 ? .idle : .tracking) }
            else { setStatus(.idleUnavailable) }
        }
        onObservation?(value)
    }
    func updateProgress(seconds: TimeInterval, threshold: TimeInterval) {
        let next = UsageProgress(seconds: seconds, threshold: threshold)
        if progress != next { progress = next }
    }
    private func setStatus(_ value: Status) { if status != value { status = value } }
    static func quietTime(includeMovement: Bool = false) -> TimeInterval? {
        var types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp, .scrollWheel]
        if includeMovement { types += [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged] }
        let values = types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return values.min()
    }
    func statusText(japanese: Bool) -> String {
        switch status {
        case .off: return japanese ? "案内はオフです。" : "Suggestions are off."
        case .unavailable: return japanese ? "対象アプリが見つかりません。起動後に再確認します。" : "Selected app not found. We'll check when it opens."
        case .waiting: return japanese ? "対象アプリを前面にすると時間を数えます。" : "Time counts while your selected app is in front."
        case .tracking: return japanese ? "対象アプリの利用時間を集計しています。" : "Counting time in your selected app."
        case .idle: return japanese ? "5分以上操作がないため、計測を一時停止しています。" : "Counting is paused after five minutes without activity."
        case .idleUnavailable: return japanese ? "無操作時間を確認できないため計測を保留しています。" : "Counting is paused because idle time is unavailable."
        case .paused: return japanese ? "今日は案内を休止しています。" : "Suggestions are paused for today."
        case .suspended: return japanese ? "画面またはMacの休止中は計測しません。" : "Counting is paused while the screen or Mac is asleep."
        }
    }
}
