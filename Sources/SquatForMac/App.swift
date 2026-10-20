import AppKit
import SwiftUI
import Combine
import QuartzCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let preview = Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27"
    private var store: MoveStore!
    private var settings: AppSettings!
    private var coordinator: AppCoordinator!
    private var usage: RefreshUsageService!
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var subscriptions = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    private let presentation = RefreshPresentation()
    private var terminating = false
    private var cameraLayout = false
    private var lastSize = RefreshGeometry.home
    private var menuTracking = false
    private var menuDisplayTimer: Timer?
    private var menuSummary: RefreshMenuSummaryView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if !preview, DownloadedAppInstaller.offerIfNeeded() { return }
        let configuration: PreviewConfiguration
        do { configuration = try PreviewConfiguration.make(preview: preview) }
        catch { NSApp.terminate(nil); return }
        let defaults = configuration.defaults
        let history = WorkoutHistory(defaults: defaults, calendar: ProgressCalendarModel.localCalendar(), now: { configuration.fixedDate ?? Date() }, databaseURL: configuration.databaseURL, synchronousWrites: false)
        settings = AppSettings(defaults: defaults); store = MoveStore(defaults: defaults, history: history)
        coordinator = AppCoordinator(store: store, settings: settings)
        usage = RefreshUsageService(defaults: defaults, settings: settings, coordinator: coordinator, openApp: { [weak self] in self?.showPanel() })
        panel = RefreshAppPanel(contentRect: NSRect(origin: .zero, size: RefreshGeometry.home), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Squat for Mac"; panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true; panel.collectionBehavior.insert(.fullScreenPrimary); panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.level = .normal; panel.delegate = self
        let host = NSHostingView(rootView: RefreshRootView(coordinator: coordinator, presentation: presentation, settings: settings, usage: usage, history: history, store: store).ignoresSafeArea())
        host.sizingOptions = []; panel.contentView = host
        coordinator.onScreenChange = { [weak self] screen in
            guard let self else { return }
            let previous = self.presentation.screen
            let camera = screen == .prepare || screen == .workout || previous == .prepare || previous == .workout
            let staged = !camera && (screen == .history || previous == .history) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            self.presentation.show(screen, animated: staged) { [weak self] completion in
                self?.updateWindow(screen, completion: completion)
            }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "figure.strengthtraining.functional", accessibilityDescription: "Squat for Mac")
        rebuildMenus()
        settings.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard self?.menuTracking != true else { return }; self?.rebuildMenus()
        }.store(in: &subscriptions)
        usage.start(); observeSystem(); updateWindow(.home); panel.center(); clamp(); showPanel()
        if preview {
            if let screen = CommandLine.arguments.first(where: { $0.hasPrefix("--review-screen=") }).map({ String($0.dropFirst(16)) }) {
                if screen == "settings" { coordinator.openSettings() }
                if screen == "detail" { coordinator.openHistory() }
                if screen == "result" { coordinator.reviewResult() }
            }
            if let style = CommandLine.arguments.first(where: { $0.hasPrefix("--review-notification=") }).flatMap({ RefreshNotificationStyle(rawValue: String($0.dropFirst(22))) }) {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.5) { self.usage.test(style) }
            }
            if let state = CommandLine.arguments.first(where: { $0.hasPrefix("--review-camera-state=") }).map({ String($0.dropFirst(22)) }) {
                coordinator.start(demo: true,target: 30); store.configureCameraReviewState(state)
            }
            if CommandLine.arguments.contains("--review-sequence=detail-home") {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.4) { self.coordinator.openHistory() }
                DispatchQueue.main.asyncAfter(deadline: .now()+1.1) { self.coordinator.goHome() }
            }
            captureIfRequested()
        }
    }
    private func rebuildMenus() {
        let menu = NSMenu(); menu.delegate = self
        let summary = NSMenuItem()
        let summaryView = RefreshMenuSummaryView()
        summaryView.update(settings: settings, usage: usage)
        summary.view = summaryView; menuSummary = summaryView
        menu.addItem(summary); menu.addItem(.separator())
        add(menu, settings.t("Squatを開く", "Open Squat"), #selector(showHome))
        add(menu, "Go Squat", #selector(startWorkout))
        add(menu, settings.t("設定", "Settings"), #selector(showSettings), key: ",")
        if preview {
            menu.addItem(.separator())
            add(menu, "Review: Home", #selector(showHome))
            add(menu, "Review: Detail", #selector(showDetail))
            add(menu, "Review: Result (demo)", #selector(showResult))
            add(menu, "Review: AI notification", #selector(blueNotification))
            add(menu, "Review: Countdown notification", #selector(countdownNotification))
            add(menu, "Review: Camera-free demo", #selector(startDemo))
        }
        menu.addItem(.separator()); add(menu, settings.t("Squatを終了", "Quit Squat"), #selector(quit), key: "q")
        statusItem.menu = menu
        let main = NSMenu(), appItem = NSMenuItem(); let app = NSMenu()
        add(app, settings.t("設定", "Settings"), #selector(showSettings), key: ","); add(app, "Quit Squat", #selector(quit), key: "q")
        let windowItem = NSMenuItem(title: "Window", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "Window")
        for (title, selector, key) in [("Close", #selector(NSWindow.performClose(_:)), "w"), ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"), ("Zoom", #selector(NSWindow.performZoom(_:)), "")] {
            windowMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        windowItem.submenu = windowMenu; main.addItem(windowItem)
        appItem.submenu = app; main.addItem(appItem); NSApp.mainMenu = main
    }
    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
    }
    func menuWillOpen(_ menu: NSMenu) {
        menuTracking = true; refreshMenuSummary()
        menuDisplayTimer?.invalidate()
        let timer = Timer(timeInterval: 1,repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMenuSummary() }
        }
        RunLoop.main.add(timer,forMode: .common)
        RunLoop.main.add(timer,forMode: .eventTracking)
        menuDisplayTimer = timer
    }
    func menuDidClose(_ menu: NSMenu) { menuTracking = false; menuDisplayTimer?.invalidate(); menuDisplayTimer = nil }
    private func refreshMenuSummary() {
        usage.refresh()
        menuSummary?.update(settings: settings, usage: usage)
    }
    private func updateWindow(_ screen: AppScreen, completion: @escaping () -> Void = {}) {
        let camera = screen == .prepare || screen == .workout
        let size = screen == .history ? RefreshGeometry.detail : RefreshGeometry.home
        if cameraLayout != camera {
            panel.styleMask = [.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView]
            panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        }
        cameraLayout = camera
        panel.backgroundColor = camera ? .black : .white
        panel.isOpaque = camera
        panel.contentMinSize = CGSize(width: min(size.width, NSScreen.main?.visibleFrame.width ?? size.width), height: min(size.height, NSScreen.main?.visibleFrame.height ?? size.height))
        guard size != lastSize || panel.frame.size != size else { completion(); return }
        let middle = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let frame = panel.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var target = NSRect(x: middle.x-frame.width/2,y: middle.y-frame.height/2,width: frame.width,height: frame.height)
        if let bounds = (panel.screen ?? NSScreen.main)?.visibleFrame {
            target.size.width = min(target.width,bounds.width); target.size.height = min(target.height,bounds.height)
            target.origin.x = min(max(target.minX,bounds.minX),bounds.maxX-target.width)
            target.origin.y = min(max(target.minY,bounds.minY),bounds.maxY-target.height)
        }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || camera {
            panel.setFrame(target, display: true); completion()
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = screen == .history || lastSize == RefreshGeometry.detail ? 0.26 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            } completionHandler: { completion() }
        }
        lastSize = size
    }
    private func clamp() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        var frame = panel.frame
        frame.size.width = min(frame.width,bounds.width); frame.size.height = min(frame.height,bounds.height)
        frame.origin.x = min(max(frame.minX,bounds.minX),bounds.maxX-frame.width)
        frame.origin.y = min(max(frame.minY,bounds.minY),bounds.maxY-frame.height)
        panel.setFrame(frame,display: true)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPanel(); return true }
    @objc private func showPanel() { clamp(); panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc private func showHome() { coordinator.goHome(); showPanel() }
    @objc private func showSettings() { guard !store.active else { return }; coordinator.openSettings(); showPanel() }
    @objc private func showDetail() { guard preview else { return }; coordinator.openHistory(); showPanel() }
    @objc private func showResult() { guard preview else { return }; coordinator.reviewResult(); showPanel() }
    @objc private func startWorkout() { showPanel(); refreshStartWithPermission(coordinator: coordinator, settings: settings) }
    @objc private func blueNotification() { usage.test(.primary) }
    @objc private func countdownNotification() { usage.test(.countdown) }
    @objc private func startDemo() { guard preview else { return }; showPanel(); coordinator.start(demo: true) }
    @objc private func quit() { NSApp.terminate(nil) }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(showSettings) || menuItem.action == #selector(startWorkout) { return !store.active && store.history.canRecord }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { coordinator.goHome(); panel.orderOut(nil); return false }
    func windowWillMiniaturize(_ notification: Notification) { if store.active { coordinator.goHome() } }
    func applicationDidHide(_ notification: Notification) { if store.active { coordinator.goHome() } }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator != nil, usage != nil, store != nil else { return .terminateNow }
        guard !terminating else { return .terminateLater }; terminating = true
        coordinator.goHome(); usage.stop()
        let group = DispatchGroup(); var saved = false
        group.enter(); store.history.flush { saved = $0; group.leave() }
        group.enter(); store.camera.stop { group.leave() }
        group.notify(queue: .main) {
            if !saved { self.terminating = false; self.usage.start(); self.showPanel() }
            NSApp.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
    private func observeSystem() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification,NSWorkspace.screensDidSleepNotification,NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name,object: nil,queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.coordinator.goHome(); self?.usage.suspend() } })
        }
        for name in [NSWorkspace.didWakeNotification,NSWorkspace.screensDidWakeNotification,NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name,object: nil,queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.usage.resume() } })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSCalendarDayChanged,object: nil,queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.store.history.objectWillChange.send(); self?.usage.calendarChanged() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange,object: nil,queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.store.history.refreshCalendarForCurrentTimeZone(); self?.usage.calendarChanged() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,object: nil,queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.clamp() } })
    }
    private func captureIfRequested() {
        guard let path = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }).map({ String($0.dropFirst(10)) }), path.hasPrefix("/private/tmp/") else { return }
        let delay = CommandLine.arguments.first(where: { $0.hasPrefix("--capture-delay=") }).flatMap { Double($0.dropFirst(16)) } ?? 1
        DispatchQueue.main.asyncAfter(deadline: .now()+max(1,min(12,delay))) {
            var target = CommandLine.arguments.contains(where: { $0.hasPrefix("--review-notification=") }) ? NSApp.windows.first(where: { $0 !== self.panel && $0.frame.width == 400 && $0.frame.height == 100 }) : self.panel
            if CommandLine.arguments.contains(where: { $0.hasPrefix("--review-sheet=") }) {
                while let sheet = target?.attachedSheet { target = sheet }
            }
            if let view = target?.contentView {
                view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds,to: bitmap)
                    if let data = bitmap.representation(using: .png,properties: [:]) { try? data.write(to: URL(fileURLWithPath: path)) }
                }
            }
            if let frameView = self.panel.contentView?.superview, let bitmap = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) {
                frameView.cacheDisplay(in: frameView.bounds,to: bitmap)
                if let data = bitmap.representation(using: .png,properties: [:]) { try? data.write(to: URL(fileURLWithPath: path+"-window.png")) }
            }
            if CommandLine.arguments.contains("--capture-today") {
                let export = RefreshShareController()
                Task {
                    await export.prepare(TodayCardSnapshot.make(history: self.store.history,usage: self.usage))
                    try? export.writeReviewPNG(to: URL(fileURLWithPath: path+".today.png"))
                }
            }
            if CommandLine.arguments.contains("--capture-total") {
                let export = RefreshShareController()
                Task {
                    await export.prepare(TotalCardSnapshot.make(history: self.store.history,usage: self.usage))
                    try? export.writeReviewPNG(to: URL(fileURLWithPath: path+".total.png"))
                }
            }
            let metadata: [String: Any] = ["screen": String(describing: self.coordinator.screen), "goal": self.store.goal,
                "language": self.settings.language.rawValue, "workoutActive": self.store.active,
                "cameraRunning": self.store.camera.session.isRunning,
                "notificationPanelsVisible": NSApp.windows.filter { $0 !== self.panel && $0.isVisible && $0.frame.width == 400 && $0.frame.height == 100 }.count,
                "width": self.panel.contentView?.bounds.width ?? 0, "height": self.panel.contentView?.bounds.height ?? 0,
                "preview": self.preview,
                "presentationScreen": String(describing: self.presentation.screen),
                "contentOpacity": self.presentation.opacity, "transitioning": self.presentation.isTransitioning,
                "interval": self.settings.usageReminderInterval.rawValue,
                "todayReps": self.store.history.todayReps, "lifetimeReps": self.store.history.lifetimeReps,
                "reviewSheetAttached": self.panel.attachedSheet != nil,
                "nativeWindowButtons": [NSWindow.ButtonType.closeButton,.miniaturizeButton,.zoomButton].map { self.panel.standardWindowButton($0)?.isHidden == false },
                "sessionTarget": self.store.sessionTarget,
                "count": self.store.count,
                "state": String(describing: self.store.state),
                "windowWidth": self.panel.frame.width, "windowHeight": self.panel.frame.height]
            if let data = try? JSONSerialization.data(withJSONObject: metadata,options: [.prettyPrinted,.sortedKeys]) { try? data.write(to: URL(fileURLWithPath: path+".json")) }
            if CommandLine.arguments.contains("--capture-quit") {
                // Exit from a run-loop event, so terminateLater can service main-queue save callbacks.
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in NSApp.terminate(nil) }
            }
        }
    }
}

private final class RefreshAppPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Native controls update immediately inside NSMenu's tracking run loop.
@MainActor private final class RefreshMenuSummaryView: NSView {
    private let heading = NSTextField(labelWithString: "")
    private let labels = (0..<4).map { _ in NSTextField(labelWithString: "") }
    private let values = (0..<4).map { _ in NSTextField(labelWithString: "") }
    private let progress = NSProgressIndicator()
    private let state = NSTextField(wrappingLabelWithString: "")
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0,y: 0,width: 320,height: 188))
        heading.font = .systemFont(ofSize: 12,weight: .semibold)
        heading.frame = NSRect(x: 14,y: 10,width: 292,height: 17)
        addSubview(heading)
        for i in 0..<4 {
            let y = 34 + CGFloat(i) * 23
            labels[i].font = .systemFont(ofSize: 13)
            labels[i].frame = NSRect(x: 14,y: y,width: 175,height: 18)
            values[i].font = .monospacedDigitSystemFont(ofSize: 13,weight: .regular)
            values[i].alignment = .right
            values[i].frame = NSRect(x: 189,y: y,width: 117,height: 18)
            addSubview(labels[i]); addSubview(values[i])
        }
        progress.style = .bar; progress.isIndeterminate = false
        progress.minValue = 0; progress.maxValue = 1; progress.controlSize = .small
        progress.frame = NSRect(x: 14,y: 128,width: 292,height: 8)
        addSubview(progress)
        state.font = .systemFont(ofSize: 12); state.textColor = .secondaryLabelColor
        state.maximumNumberOfLines = 2
        state.frame = NSRect(x: 14,y: 146,width: 292,height: 34)
        addSubview(state)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(settings: AppSettings, usage: RefreshUsageService) {
        let snapshot = usage.menuUsage
        heading.stringValue = settings.t("今日", "Today")
        let titles = ["ChatGPT/Codex", "Claude", "Desk time", settings.t("次の通知まで（AI利用）", "Next reminder (AI use)")]
        let times = [snapshot.chatgptDisplay, snapshot.claudeDisplay, snapshot.deskDisplay, snapshot.remainingDisplay]
        for i in 0..<4 {
            labels[i].stringValue = titles[i]; values[i].stringValue = times[i]
        }
        progress.doubleValue = snapshot.fraction
        state.stringValue = usage.stateText
        toolTip = settings.t("選択したAIアプリを前面で使った時間を合算します。別のアプリの操作中や操作がない間は、通知までのAI利用時間は減りません。再通知は通常の通知間隔、または前回の通知から45分後の早い方で待機します。", "Active use of selected AI apps is combined. Time in other apps or while idle does not reduce the AI time remaining. A follow-up becomes due at the next regular interval or 45 minutes after the previous reminder, whichever is earlier.")
    }
}

@main enum SquatForMac {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
