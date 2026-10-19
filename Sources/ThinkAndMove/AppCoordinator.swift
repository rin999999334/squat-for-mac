import Foundation
import Combine

@MainActor final class AppCoordinator: ObservableObject {
    let store: MoveStore
    let settings: AppSettings
    @Published var screen: AppScreen
    @Published var showSettings = false
    @Published private(set) var result: SessionResult?
    var onScreenChange: ((AppScreen) -> Void)?
    private var observations: Set<AnyCancellable> = []
    private var settingsReturn: AppScreen = .home

    init(store: MoveStore, settings: AppSettings) {
        self.store = store; self.settings = settings
        screen = .home
        store.onGoalReached = { [weak self] in self?.presentResult(completed: true) }
        store.onStorageFailure = { [weak self] in self?.presentResult(completed: false) }
        store.$preparing.receive(on: DispatchQueue.main).sink { [weak self] preparing in
            guard let self, self.store.active, !preparing, !self.store.preparing else { return }
            self.setScreen(.workout)
        }.store(in: &observations)
        store.history.$saveState.receive(on: DispatchQueue.main).sink { [weak self] state in
            guard let self, state == .failed, self.store.history.saveState == .failed, self.store.active, !self.store.demo else { return }
            self.store.stop()
            self.presentResult(completed: false)
        }.store(in: &observations)
    }

    func openSettings() {
        guard !store.active, screen != .welcome else { return }
        settingsReturn = screen == .history || screen == .result ? screen : .home
        showSettings = true
        setScreen(.settings)
    }
    func closeSettings() { showSettings = false; goHome() }
    func openHistory() { guard !store.active else { return }; showSettings = false; setScreen(.history) }
    func reviewResult() {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", !store.active else { return }
        result = SessionResult(id: UUID(), count: 9, target: 9, duration: 0, completed: true, isDemo: true)
        setScreen(.result)
    }
    func showWelcomePreview() {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", !store.active else { return }
        showSettings = false
        setScreen(.welcome)
    }
    func completeOnboarding() {
        settings.onboardingCompleted = true
        goHome()
    }
    func start(tutorial: Bool = false, demo: Bool = false, target: Int? = nil) {
        guard !store.active else { return }
        guard demo || store.history.canRecord else { showSettings = false; setScreen(.home); return }
        if tutorial { settings.onboardingCompleted = true }
        result = nil; showSettings = false
        setScreen(.prepare)
        store.start(demo: demo, target: tutorial ? 5 : target)
    }
    func goHome() {
        if store.active { store.stop() }
        store.showWorkout = false
        result = nil; showSettings = false
        setScreen(.home)
    }
    func finish() {
        guard store.active else {
            if store.count > 0 { presentResult(completed: false) } else { goHome() }
            return
        }
        let wasPreparing = store.startedAt == nil
        store.stop()
        if wasPreparing && store.count == 0 { goHome() }
        else { presentResult(completed: false) }
    }
    func retrySave() { store.history.retryPendingWrites() }
    private func presentResult(completed: Bool) {
        guard result?.id != store.sessionID else { return }
        result = SessionResult(id: store.sessionID, count: store.count, target: store.sessionTarget,
                               duration: store.finishedDuration, completed: completed, isDemo: store.demo)
        setScreen(.result)
    }
    private func setScreen(_ value: AppScreen) {
        guard screen != value else { return }
        screen = value; onScreenChange?(value)
    }
}
