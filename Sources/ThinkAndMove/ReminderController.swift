import AppKit
import Combine

/// Coordinates aggregate usage and a passive card. No AX readers or AI hooks run here.
@MainActor final class ReminderController {
    private let coordinator: AppCoordinator
    private let store: MoveStore
    private let settings: AppSettings
    private let monitor: ForegroundUsageMonitor
    private let showApp: () -> Void
    private let panel = ReminderInvitationPanel()
    private var policy: UsageReminderPolicy
    private var testPresentation: ReminderPresentation?
    private var expiryTimer: Timer?
    private var scheduledDeadline: TimeInterval?
    private var observations = Set<AnyCancellable>()
    private var started = false
    private var suspended = false
    private var displayedID: UUID?
    private var appliedSettings: UsageSettings?
    private var lastPersist: TimeInterval = 0
    private var lastWorkout: UUID?
    private static let aggregateKey = "thinkAndMove.reminders.usage.aggregate.v1"

    init(coordinator: AppCoordinator, store: MoveStore, settings: AppSettings,
         monitor: ForegroundUsageMonitor, showApp: @escaping () -> Void) {
        self.coordinator = coordinator; self.store = store; self.settings = settings
        self.monitor = monitor; self.showApp = showApp
        let saved = monitor.defaults.data(forKey: Self.aggregateKey).flatMap { try? JSONDecoder().decode(UsageAggregate.self, from: $0) }
        var configuration = UsageReminderConfiguration(interval: settings.usageReminderInterval)
        if Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", CommandLine.arguments.contains("--usage-threshold=15") {
            configuration.threshold = 15; configuration.minimumNoticeInterval = 15
        }
        policy = UsageReminderPolicy(tracker: UsageTimeTracker(provider: settings.aiProvider.rawValue, date: Date(), saved: saved, configuration: configuration))
        settings.$usageRemindersEnabled.combineLatest(settings.$aiProvider, settings.$usageReminderInterval)
            .map { UsageSettings(enabled: $0, provider: $1, interval: $2) }.removeDuplicates().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applySettings() }.store(in: &observations)
        let eligibility = [
            coordinator.$screen.map { _ in () }.eraseToAnyPublisher(),
            coordinator.$showSettings.map { _ in () }.eraseToAnyPublisher(),
            store.$active.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            store.history.$saveState.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            store.history.$storageError.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]
        Publishers.MergeMany(eligibility).receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.eligibilityChanged() }.store(in: &observations)
    }
    func start() {
        guard !started else { return }
        started = true; suspended = false
        monitor.onObservation = { [weak self] in self?.receive($0) }
        monitor.onPauseToday = { [weak self] in self?.pauseToday() }
        appliedSettings = nil; applySettings()
    }
    func stop() {
        persist(); started = false; suspended = false
        policy.suspend(); testPresentation = nil; panel.hide(); displayedID = nil
        expiryTimer?.invalidate(); expiryTimer = nil; scheduledDeadline = nil; monitor.stop()
        monitor.onObservation = nil; monitor.onPauseToday = nil
    }
    func suspend() {
        guard started else { return }
        suspended = true; policy.suspend(); testPresentation = nil
        monitor.suspend(); persist(); render()
    }
    func resume() {
        guard started, suspended else { return }
        suspended = false; policy.suspend(); monitor.resume(); evaluate()
    }
    func pauseToday() {
        policy.pauseToday(at: Date()); testPresentation = nil; persist()
        monitor.configure(enabled: settings.usageRemindersEnabled, provider: settings.aiProvider, paused: true)
        render()
    }
    func calendarChanged() {
        policy.trackerCalendarChanged()
        receive(monitor.observation())
        monitor.refresh()
    }
    func startAcceleratedPreview() {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", !store.active else { return }
        var configuration = UsageReminderConfiguration()
        configuration.threshold = 15; configuration.minimumNoticeInterval = 15
        policy = UsageReminderPolicy(tracker: UsageTimeTracker(provider: settings.aiProvider.rawValue, date: Date(), configuration: configuration))
        settings.usageRemindersEnabled = true
        appliedSettings = nil
        coordinator.goHome(); applySettings()
    }
    func showTestInvitation() {
        guard started, !suspended,
              coordinator.screen != .welcome, !store.active, store.history.canRecord else { return }
        policy.suspend()
        testPresentation = ReminderPresentation(id: UUID(), kind: .displayTest, target: store.goal, shownAt: now, expiresAt: now + 8)
        render()
    }
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private func context() -> UsageReminderContext {
        UsageReminderContext(enabled: settings.usageRemindersEnabled,
            eligible: started && !suspended && coordinator.screen.allowsUsageReminder && !store.active && store.history.canRecord,
            targetIsFront: monitor.targetIsFront, inputQuietTime: ForegroundUsageMonitor.quietTime(), target: store.goal)
    }
    private func applySettings() {
        guard started else { return }
        let next = UsageSettings(enabled: settings.usageRemindersEnabled, provider: settings.aiProvider, interval: settings.usageReminderInterval)
        guard next != appliedSettings else { return }
        if let old = appliedSettings, old.provider != next.provider {
            let saved = policy.aggregate
            policy = UsageReminderPolicy(tracker: UsageTimeTracker(provider: next.provider.rawValue, date: Date(), saved: saved, configuration: policy.tracker.configuration))
        }
        if let old = appliedSettings, old.interval != next.interval {
            policy.setInterval(next.interval); testPresentation = nil
        }
        if !next.enabled { policy.resetForWorkout(); testPresentation = nil }
        appliedSettings = next
        monitor.configure(enabled: next.enabled, provider: next.provider, paused: policy.paused)
        persist(); evaluate()
    }
    private func receive(_ observation: UsageObservation) {
        guard started else { return }
        let wasPaused = policy.paused
        policy.receive(observation, context: context())
        if wasPaused != policy.paused { monitor.configure(enabled: settings.usageRemindersEnabled, provider: settings.aiProvider, paused: policy.paused) }
        if observation.time - lastPersist >= 60 { persist() }
        render()
    }
    private func eligibilityChanged() {
        guard started else { return }
        if !store.active, !store.demo, store.count > 0, store.sessionID != lastWorkout {
            lastWorkout = store.sessionID; policy.resetForWorkout(); persist()
        }
        evaluate()
    }
    private func evaluate() {
        guard started else { return }
        if let test = testPresentation, now >= test.expiresAt || suspended || store.active || !store.history.canRecord || coordinator.screen == .welcome { testPresentation = nil }
        policy.evaluate(time: now, date: Date(), context: context()); render()
    }
    private func render() {
        monitor.updateProgress(seconds: policy.aggregate.seconds, threshold: policy.tracker.configuration.threshold)
        let current = testPresentation ?? policy.presentation
        if let invitation = current {
            if displayedID != invitation.id {
                displayedID = invitation.id
                PreviewDiagnostics.record("invitation-context", values: ["screen": String(describing: coordinator.screen), "kind": invitation.kind.rawValue])
                panel.show(invitation, isJapanese: settings.isJapanese, onStart: { [weak self] in self?.accept(id: $0) }, onDismiss: { [weak self] id in
                    guard let self else { return }
                    if self.testPresentation?.id == id { self.testPresentation = nil }
                    self.policy.dismiss(id: id); self.render()
                })
                persist()
            }
        } else { panel.hide(); displayedID = nil }
        let deadline = current?.expiresAt ?? policy.nextDeadline
        guard deadline != scheduledDeadline else { return }
        expiryTimer?.invalidate(); expiryTimer = nil; scheduledDeadline = deadline
        if let deadline {
            let timer = Timer(timeInterval: max(0.01, deadline - now), repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.scheduledDeadline = nil; self?.evaluate() }
            }
            RunLoop.main.add(timer, forMode: .common); expiryTimer = timer
        }
    }
    private func accept(id: UUID) {
        guard started, !suspended else { return }
        let invitation: ReminderPresentation?
        if let test = testPresentation, test.id == id {
            invitation = now < test.expiresAt && coordinator.screen != .welcome && !store.active && store.history.canRecord ? test : nil
            testPresentation = nil
        } else { invitation = policy.accept(id: id, time: now, context: context()) }
        render()
        guard let invitation else { return }
        showApp(); coordinator.start(target: invitation.target)
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(policy.aggregate) { monitor.defaults.set(data, forKey: Self.aggregateKey) }
        lastPersist = now
    }
    private struct UsageSettings: Equatable { let enabled: Bool; let provider: AIProvider; let interval: UsageReminderInterval }
}
