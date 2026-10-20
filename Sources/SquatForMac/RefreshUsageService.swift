import AppKit
import Combine
import CoreGraphics
import Darwin

@MainActor final class RefreshUsageService: ObservableObject {
    @Published private(set) var aiDisplay = "--h--m"
    @Published private(set) var deskDisplay = "--h--m"
    @Published private(set) var progress = UsageProgress()
    private(set) var menuUsage = RefreshMenuUsageSnapshot()
    @Published private(set) var suspended = false
    @Published private(set) var idlePaused = false
    @Published private(set) var observationUnavailable = false
    let defaults: UserDefaults
    let settings: AppSettings
    private let coordinator: AppCoordinator
    private var ledger: RefreshUsageLedger
    private var cycle = RefreshReminderCycle()
    private var previous: (time: Double, date: Date, provider: AIProvider?, active: Bool)?
    private var timer: Timer?
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private var persistAt = 0.0
    private var lastDay = ""
    private var settingsStamp = ""
    private var lastWorkout: UUID?
    private var invitation: RefreshInvitation?
    private var accepted = Set<UUID>()
    private let panel = RefreshNotificationPanel()
    private var openApp: () -> Void
    private let referenceFixture: Bool

    init(defaults: UserDefaults, settings: AppSettings, coordinator: AppCoordinator, openApp: @escaping () -> Void) {
        self.defaults = defaults; self.settings = settings; self.coordinator = coordinator; self.openApp = openApp
        ledger = defaults.data(forKey: "squat.refresh.usage.v1").flatMap { try? JSONDecoder().decode(RefreshUsageLedger.self, from: $0) } ?? .init()
        // Legacy pausedDay is decoded for compatibility and is intentionally inert: the pause-today feature was removed.
        referenceFixture = CommandLine.arguments.contains("--ui-fixture=refresh-reference") && Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27"
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] in self?.settingsChanged() }.store(in: &subscriptions)
        coordinator.store.$active.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] _ in self?.workoutChanged() }.store(in: &subscriptions)
        coordinator.store.history.$saveState.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self else { return }
            self.workoutChanged()
        }.store(in: &subscriptions)
    }
    var targetIsFront: Bool { currentProvider.map(settings.selectedProviders.contains) ?? false }
    var currentProvider: AIProvider? {
        switch NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
        case "com.openai.chat", "com.openai.codex": return .chatgptDesktop
        case "com.anthropic.claudefordesktop": return .claudeDesktop
        default: return nil
        }
    }
    var sourceName: String {
        if settings.selectedProviders.count > 1 { return "ChatGPT/Claude" }
        return settings.selectedProviders.contains(.claudeDesktop) ? "Claude" : "ChatGPT/Codex"
    }
    var elapsed: Double { ledger.elapsed(settings.selectedProviders) }
    var stateText: String {
        if !settings.usageRemindersEnabled { return settings.t("通知はオフです", "Reminders are off") }
        if suspended { return settings.t("計測を一時停止しています", "Tracking is paused") }
        if observationUnavailable { return settings.t("利用時間を取得できません", "Time tracking unavailable") }
        if idlePaused { return settings.t("操作がないため計測を一時停止しています", "Counting is paused while idle") }
        if !settings.usageCollectionAllowed || settings.selectedProviders.isEmpty { return settings.t("集計するAIアプリを選んでください", "Choose AI apps to count") }
        if !targetIsFront { return settings.t("選択したAIアプリの利用を待っています", "Waiting for a selected AI app") }
        if let deadline = cycle.followupDeadline {
            let minutes = max(0, Int(ceil((deadline - Self.continuousNow) / 60)))
            return minutes == 0 ? settings.t("再通知のタイミングを待っています", "Reminder pending") : settings.t("再通知まで：\(minutes)分", "Next reminder: \(minutes) min")
        }
        return settings.t("利用時間を計測中", "Counting usage time")
    }
    func start() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } }
        timer.tolerance = 0.15
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .eventTracking)
        self.timer = timer
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.sample() } })
        settingsChanged(); sample()
    }
    func refresh() { sample() }
    func stop() {
        timer?.invalidate(); timer = nil; persist(); panel.hide()
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver); observers = []
    }
    func suspend() { suspended = true; previous = nil; invalidate(cancelCycle: false); persist() }
    func resume() { suspended = false; previous = nil; invalidate(cancelCycle: false); sample() }
    func calendarChanged() { previous = nil; invalidate(); sample() }
    func test(_ style: RefreshNotificationStyle) {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", !coordinator.store.active else { return }
        present(style, test: true)
    }
    private func settingsChanged() {
        let stamp = "\(settings.usageRemindersEnabled)|\(settings.selectedProviders.map(\.rawValue).sorted())|\(settings.usageReminderInterval.rawValue)|\(settings.usageCollectionAllowed)"
        if stamp != settingsStamp {
            settingsStamp = stamp; previous = nil; invalidate()
        }
        updateDisplays(); objectWillChange.send()
    }
    private func sample() {
        let date = Date(), time = ProcessInfo.processInfo.systemUptime
        let day = RefreshUsageLedger.dayKey(date)
        if day != lastDay { lastDay = day; invalidate() }
        let provider = currentProvider
        let idle = ForegroundUsageMonitor.quietTime(includeMovement: true)
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let locked = session?["CGSSessionScreenIsLocked"] as? Bool ?? false
        let idleNow = idle.map { $0.isFinite && $0 >= 300 } ?? false
        if idlePaused != idleNow { idlePaused = idleNow }
        let unavailable = session == nil || idle == nil
        if observationUnavailable != unavailable { observationUnavailable = unavailable }
        let active = !suspended && !locked && !coordinator.store.active && session != nil && (idle.map { $0 < 300 && $0.isFinite } ?? false)
        if !referenceFixture, let prev = previous, active, prev.active, prev.provider == provider {
            let delta = time - prev.time
            if delta > 0 && delta <= 5 {
                let cal = Calendar.current
                let boundary = cal.startOfDay(for: date)
                let before = max(0, min(delta, boundary.timeIntervalSince(prev.date)))
                if RefreshUsageLedger.dayKey(prev.date) != day && before > 0 {
                    ledger.add(before, day: RefreshUsageLedger.dayKey(prev.date), provider: provider,
                               countAI: settings.usageCollectionAllowed && provider.map(settings.selectedProviders.contains) == true, countDesk: settings.deskCollectionAllowed)
                }
                ledger.add(delta - before, day: day, provider: provider,
                           countAI: settings.usageCollectionAllowed && provider.map(settings.selectedProviders.contains) == true, countDesk: settings.deskCollectionAllowed)
            }
        }
        previous = (time, date, provider, active)
        updateDisplays()
        if time - persistAt >= 60 { persist() }
        if let notice = invitation {
            if !coordinator.store.history.canRecord || coordinator.store.active || suspended || (!notice.isTest && (!settings.usageRemindersEnabled || !targetIsFront)) {
                panel.hide(); invitation = nil
            }
            return
        }
        guard commonEligibility(active: active) else { return }
        let ready = elapsed >= settings.usageReminderInterval.seconds
        if let style = cycle.candidate(now: Self.continuousNow, regularReady: ready) { present(style, test: false) }
    }
    private func commonEligibility(active: Bool = true) -> Bool {
        active && NSEvent.pressedMouseButtons == 0 && previous?.active == true && !suspended && settings.usageRemindersEnabled && settings.usageCollectionAllowed && !settings.selectedProviders.isEmpty && targetIsFront && !coordinator.store.active && coordinator.screen.allowsUsageReminder && coordinator.store.history.canRecord
    }
    private func invalidate(cancelCycle: Bool = true) {
        if cancelCycle { cycle.cancel() }
        panel.hide(); invitation = nil
    }
    private func workoutChanged() {
        if coordinator.store.active { invalidate(cancelCycle: false); previous = nil }
        if !coordinator.store.active, !coordinator.store.demo, coordinator.store.count > 0,
           coordinator.store.history.saveState == .recorded, coordinator.store.sessionID != lastWorkout {
            lastWorkout = coordinator.store.sessionID; ledger.reminder = [:]; invalidate(); persist()
        }
    }
    private func present(_ style: RefreshNotificationStyle, test: Bool) {
        guard !coordinator.store.active, coordinator.store.history.canRecord, !suspended else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let item = RefreshInvitation(id: UUID(), style: style, target: min(30, max(1, coordinator.store.goal)), source: sourceName,
                                     seconds: ledger.total(settings.selectedProviders, day: RefreshUsageLedger.dayKey(coordinator.store.history.currentDate)), shownAt: now, expiresAt: now + (style == .countdown ? 10 : 8), isTest: test)
        if panel.show(item, settings: settings, onStart: { [weak self] in self?.accept($0) }, onDismiss: { [weak self] id in
            guard let self, self.invitation?.id == id else { return }; self.panel.hide(); self.invitation = nil
        }, onExpired: { [weak self] id in
            guard let self, self.invitation?.id == id else { return }
            self.invitation = nil
        }) {
            invitation = item
            if !test { cycle.displayed(style, at: Self.continuousNow); ledger.consume(at: Date()); persist() }
        }
    }
    private func accept(_ id: UUID) {
        guard let value = invitation, value.id == id, !accepted.contains(id), ProcessInfo.processInfo.systemUptime < value.expiresAt,
              !suspended, !coordinator.store.active, coordinator.store.history.canRecord,
              value.isTest || settings.usageRemindersEnabled else { return }
        accepted.insert(id); if accepted.count > 100 { accepted = [id] }
        panel.hide(); invitation = nil; openApp(); refreshStartWithPermission(coordinator: coordinator, settings: settings, target: value.target)
    }
    private func updateDisplays() {
        let day = RefreshUsageLedger.dayKey(Date())
        let ai = aiTime(on: day)
        let desk = deskTime(on: day)
        if aiDisplay != ai { aiDisplay = ai }; if deskDisplay != desk { deskDisplay = desk }
        let value = UsageProgress(seconds: elapsed, threshold: settings.usageReminderInterval.seconds)
        if value != progress { progress = value }
        let daily = ledger.days[day]
        func providerSeconds(_ provider: AIProvider) -> Double? {
            guard daily?.measuredAI.contains(provider.rawValue) == true else { return nil }
            return daily?.ai[provider.rawValue] ?? 0
        }
        let menuValue = RefreshMenuUsageSnapshot(chatgptSeconds: providerSeconds(.chatgptDesktop),
                                                claudeSeconds: providerSeconds(.claudeDesktop),
                                                deskSeconds: daily?.measuredDesk == true ? daily?.desk : nil,
                                                elapsedSeconds: elapsed, thresholdSeconds: settings.usageReminderInterval.seconds)
        if menuValue != menuUsage { menuUsage = menuValue }
    }
    func aiTime(on day: String) -> String {
        guard !settings.selectedProviders.isEmpty, let value = ledger.days[day], !value.measuredAI.isDisjoint(with: Set(settings.selectedProviders.map(\.rawValue))) else { return "--h--m" }
        return RefreshGeometry.duration(ledger.total(settings.selectedProviders, day: day))
    }
    func deskTime(on day: String) -> String {
        guard let value = ledger.days[day], value.measuredDesk else { return "--h--m" }
        return RefreshGeometry.duration(value.desk)
    }
    func summary(from start: Date, through end: Date, day: Date? = nil, calendar: Calendar) -> (String, String) {
        let first = RefreshUsageLedger.dayKey(day ?? start, calendar: calendar)
        let last = RefreshUsageLedger.dayKey(day ?? end, calendar: calendar)
        let values = ledger.days.filter { $0.key >= first && $0.key <= last }
        let selected = Set(settings.selectedProviders.map(\.rawValue))
        let aiKnown = values.values.contains { !$0.measuredAI.isDisjoint(with: selected) }
        let deskKnown = values.values.contains { $0.measuredDesk }
        let ai = values.values.reduce(0.0) { sum, v in sum + selected.reduce(0.0) { $0 + (v.ai[$1] ?? 0) } }
        let desk = values.values.reduce(0.0) { $0 + $1.desk }
        return (aiKnown ? RefreshGeometry.duration(ai) : "--h--m", deskKnown ? RefreshGeometry.duration(desk) : "--h--m")
    }
    func lifetimeSummary() -> RefreshUsageTotals {
        RefreshUsageTotals(days: Array(ledger.days.values), selected: Set(settings.selectedProviders.map(\.rawValue)))
    }
    private static var continuousNow: Double {
        var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
        return Double(mach_continuous_time()) * Double(info.numer) / Double(info.denom) / 1_000_000_000
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: "squat.refresh.usage.v1") }
        persistAt = ProcessInfo.processInfo.systemUptime
    }
}
