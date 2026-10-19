import AppKit
import ApplicationServices
import Combine
import Foundation

enum AIIntegrationStatus: String {
    case disabled, unverifiedProfile, accessibilityPermissionRequired, monitoring
    case applicationUnavailable, profileVersionMismatch, verifyingProfile, sourceUnavailable, ordinaryChatNotVerified

    func message(isJapanese: Bool) -> String {
        switch self {
        case .disabled:
            return isJapanese ? "自動案内はオフです。メニューバーからいつでも始められます。" : "Automatic invitations are off. Start anytime from the menu bar."
        case .unverifiedProfile:
            return isJapanese ? "通常チャットの接続を3段階で確認すると、自動案内を使えます。" : "Verify your ordinary desktop chat in three steps to enable invitations."
        case .accessibilityPermissionRequired:
            return isJapanese ? "自動案内にはアクセシビリティの許可が必要です。手動開始は使えます。" : "Automatic invitations need Accessibility permission. Manual start is available."
        case .monitoring:
            return isJapanese ? "確認済みの通常チャットの待ち時間を見ています。会話本文は読みません。" : "Watching verified desktop chat waiting time. Conversation text is not read."
        case .applicationUnavailable:
            return isJapanese ? "選択した通常チャットアプリが見つかりません。Codex・Claude Codeは対象外です。" : "The selected ordinary chat app was not found. Codex and Claude Code are not supported."
        case .profileVersionMismatch:
            return isJapanese ? "アプリの版が変わりました。接続をもう一度確認してください。" : "The chat app version changed. Verify the connection again."
        case .verifyingProfile:
            return isJapanese ? "接続を確認中です。この間、自動案内は出しません。" : "Verifying the connection. Invitations are paused during setup."
        case .ordinaryChatNotVerified:
            return isJapanese ? "アプリは見つかりましたが、通常チャットの選択を確認できません。Code・Work等では案内しません。" : "The app was found, but ordinary Chat mode could not be verified. Code and Work modes never invite."
        case .sourceUnavailable:
            return isJapanese ? "通常チャットのウィンドウを確認できないため、案内を控えています。" : "Invitations are paused because the ordinary chat window cannot be verified."
        }
    }
}

struct AIInstalledApplication: Equatable {
    let path: String
    let bundleID: String
    let version: String
    let build: String
    var identity: DesktopAIApplicationIdentity { .init(bundleID: bundleID, version: version, build: build) }
}

@MainActor
final class AIActivityMonitor: ObservableObject {
    @Published private(set) var status: AIIntegrationStatus = .disabled
    @Published private(set) var installedApplications: [AIInstalledApplication] = []
    @Published private(set) var accessibilityTrusted = false
    @Published private(set) var setupStep: AIConnectionSetupStep = .idle
    @Published private(set) var setupError: String?
    @Published private(set) var provider: AIProvider = .chatgptDesktop
    var onSnapshot: ((AIActivitySnapshot) -> Void)?
    var onSourceChanged: ((AIActivitySource?) -> Void)?
    var available: Bool { profileVerified }
    var profileVerified: Bool {
        guard let application = selectedApplication else { return false }
        return profiles.contains { $0.matches(application.identity, provider: provider) }
    }

    private let defaults: UserDefaults
    private let reader = DesktopAXReader()
    private static let profileKey = "thinkAndMove.ai.desktopProfiles.v1"
    private var profiles: [DesktopAIProfile] = []
    private var enabled = false
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var readInFlight = false
    private var operationID = UUID()
    private var tracker = AIActivityTracker()
    private var source: AIActivitySource?
    private var sourceWindowID: UUID?
    private var sequence: UInt64 = 0
    private var verification = DesktopAIProfileVerification()
    private var setupWindowID: UUID?
    private var setupApplication: DesktopAIApplicationIdentity?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode([DesktopAIProfile].self, from: data) {
            profiles = saved.filter(\.isValid)
        }
        refreshAvailability()
    }

    func start(enabled: Bool, provider: AIProvider = .chatgptDesktop) {
        invalidateRead(); stopTimer(); retireSource()
        self.enabled = enabled; self.provider = provider
        verification = DesktopAIProfileVerification(); setupWindowID = nil; setupApplication = nil; setupError = nil
        setupStep = .idle
        installObservers()
        refreshAvailability()
        setupStep = profileVerified ? .connected : .idle
    }

    func stop() {
        enabled = false; invalidateRead(); stopTimer(); retireSource(); reader.reset()
        verification = DesktopAIProfileVerification(); setupWindowID = nil; setupApplication = nil; setupError = nil
        setupStep = profileVerified ? .connected : .idle
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver); observers.removeAll()
        status = .disabled
    }

    func beginSetup(provider: AIProvider) {
        invalidateRead(); stopTimer(); retireSource(); reader.reset()
        self.provider = provider
        verification = DesktopAIProfileVerification(); setupWindowID = nil; setupApplication = nil; setupError = nil
        setupStep = .captureIdle
        installObservers(); refreshAvailability()
    }

    func captureSetupStep() {
        guard setupStep.isCapturing, !readInFlight else { return }
        refreshAvailability()
        guard accessibilityTrusted else { setupError = "Allow Accessibility, then try this step again."; return }
        guard let request = selectedRequest() else { setupError = "Open the selected ordinary desktop chat app, then try again."; return }
        let expectedStep = setupStep
        let token = operationID
        setupError = nil; readInFlight = true
        reader.read(request) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.operationID == token, self.setupStep == expectedStep else { return }
                self.readInFlight = false
                guard case .observation(let observation) = result else {
                    self.resetVerificationIfSourceLost()
                    self.setupError = "The chat window was not readable. Keep it open and visible, then retry."; return
                }
                if let window = self.setupWindowID,
                   window != observation.windowID || self.setupApplication != observation.application {
                    self.resetVerificationIfSourceLost()
                    self.setupError = "The chat window or app version changed. Start again with the idle step."; return
                }
                guard observation.isOrdinaryChat else {
                    self.resetVerificationIfSourceLost(); self.status = .ordinaryChatNotVerified
                    self.setupError = "Ordinary Chat mode could not be verified. Select Chat; Code, Work and Cowork are not supported."; return
                }
                switch expectedStep {
                case .captureIdle:
                    guard self.verification.captureIdle(observation, provider: self.provider) else {
                        self.setupError = "Wait until the reply has finished. Ambiguous Stop or approval controls cannot be used."; return
                    }
                    self.setupWindowID = observation.windowID; self.setupApplication = observation.application
                    self.setupStep = .captureRunning
                case .captureRunning:
                    guard self.verification.captureRunning(observation, provider: self.provider) else {
                        self.setupError = "A unique generation Stop button was not verified. Capture while a reply is being generated."; return
                    }
                    self.setupStep = .captureCompletion
                case .captureCompletion:
                    guard let profile = self.verification.complete(observation, provider: self.provider) else {
                        self.setupError = "Wait until generation finishes and its Stop button disappears, then capture again."; return
                    }
                    self.profiles.removeAll { $0.provider == self.provider }
                    self.profiles.append(profile)
                    if let encoded = try? JSONEncoder().encode(self.profiles) { self.defaults.set(encoded, forKey: Self.profileKey) }
                    self.setupStep = .connected; self.setupError = nil
                    self.verification = DesktopAIProfileVerification(); self.setupWindowID = nil; self.setupApplication = nil
                    // Monitoring starts with a new epoch, requiring a fresh idle
                    // observation and two running observations before inviting.
                    self.retireSource(); self.reader.reset(); self.refreshAvailability()
                default: break
                }
            }
        }
    }

    func cancelSetup() {
        invalidateRead(); stopTimer(); retireSource(); reader.reset()
        verification = DesktopAIProfileVerification(); setupWindowID = nil; setupApplication = nil; setupError = nil
        setupStep = profileVerified ? .connected : .idle
        refreshAvailability()
    }

    func resetProfile(provider: AIProvider) {
        profiles.removeAll { $0.provider == provider }
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.profileKey) }
        if self.provider == provider { cancelSetup() }
    }

    /// Called only by the user's explicit permission button, never by start/poll.
    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAvailability()
    }

    func refreshAvailability() {
        let wasTrusted = accessibilityTrusted
        accessibilityTrusted = AXIsProcessTrusted()
        installedApplications = discoverApplications()
        if wasTrusted && !accessibilityTrusted { invalidateRead(); retireSource(); reader.reset(); resetVerificationIfSourceLost() }
        if setupStep.isCapturing {
            stopTimer()
            status = !accessibilityTrusted ? .accessibilityPermissionRequired : selectedApplication == nil ? .applicationUnavailable : .verifyingProfile
            return
        }
        guard enabled else { stopTimer(); status = .disabled; return }
        guard selectedApplication != nil else { stopTimer(); retireSource(); status = .applicationUnavailable; return }
        guard profileVerified else {
            stopTimer(); retireSource()
            status = profiles.contains(where: { $0.provider == provider }) ? .profileVersionMismatch : .unverifiedProfile
            return
        }
        guard accessibilityTrusted else { stopTimer(); retireSource(); status = .accessibilityPermissionRequired; return }
        if timer == nil {
            status = .monitoring
            let token = operationID
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in guard let self, self.operationID == token else { return }; self.poll() }
            }
            poll()
        }
    }

    func setupErrorMessage(isJapanese: Bool) -> String? {
        guard let setupError else { return nil }
        guard isJapanese else { return setupError }
        let translations = [
            "Allow Accessibility, then try this step again.": "アクセシビリティを許可してから、もう一度記録してください。",
            "Open the selected ordinary desktop chat app, then try again.": "選択した通常チャットアプリを開いてから、もう一度記録してください。",
            "The chat window was not readable. Keep it open and visible, then retry.": "チャットのウィンドウを確認できません。最小化せずに開いた状態で、もう一度お試しください。",
            "The chat window or app version changed. Start again with the idle step.": "ウィンドウまたはアプリの版が変わりました。待機状態の記録からやり直してください。",
            "Ordinary Chat mode could not be verified. Select Chat; Code, Work and Cowork are not supported.": "通常チャットの選択を確認できません。Chatを選んでください。Code・Work・Coworkは対象外です。",
            "Wait until the reply has finished. Ambiguous Stop or approval controls cannot be used.": "回答が終了してから記録してください。汎用の停止・承認待ちの操作部品では確認できません。",
            "A unique generation Stop button was not verified. Capture while a reply is being generated.": "生成専用の停止ボタンを1つだけ確認できませんでした。回答の生成中に記録してください。",
            "Wait until generation finishes and its Stop button disappears, then capture again.": "生成が終了し、停止ボタンが消えてからもう一度記録してください。"
        ]
        return translations[setupError] ?? "接続を確認できませんでした。対象アプリの状態を確認して、もう一度お試しください。"
    }

    private var selectedApplication: AIInstalledApplication? {
        let wanted = DesktopAIApplicationIdentity.bundleID(for: provider)
        let candidates = installedApplications.filter { $0.bundleID == wanted || (provider == .chatgptDesktop && $0.bundleID == "com.openai.codex") }
        let runningPaths = Set(candidates.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).compactMap { $0.bundleURL?.path } })
        return candidates.first { runningPaths.contains($0.path) } ?? candidates.first
    }
    private func selectedRequest() -> DesktopAXReadRequest? {
        guard let application = selectedApplication,
              let running = NSRunningApplication.runningApplications(withBundleIdentifier: application.bundleID).first(where: { $0.bundleURL?.path == application.path }),
              application.identity.isSupported(for: provider) else { return nil }
        return DesktopAXReadRequest(processID: running.processIdentifier, provider: provider, application: application.identity)
    }
    private func discoverApplications() -> [AIInstalledApplication] {
        var urls: [URL] = []
        for provider in AIProvider.allCases {
            let id = DesktopAIApplicationIdentity.bundleID(for: provider)
            urls += NSRunningApplication.runningApplications(withBundleIdentifier: id).compactMap(\.bundleURL)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { urls.append(url) }
        }
        urls += NSRunningApplication.runningApplications(withBundleIdentifier: "com.openai.codex").compactMap(\.bundleURL)
        if let integrated = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex") { urls.append(integrated) }
        for directory in [URL(fileURLWithPath: "/Applications", isDirectory: true), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)] {
            for name in ["ChatGPT.app", "Claude.app"] { urls.append(directory.appendingPathComponent(name, isDirectory: true)) }
        }
        var paths = Set<String>()
        return urls.compactMap { url in
            guard paths.insert(url.path).inserted, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
            return AIInstalledApplication(path: url.path, bundleID: id,
                                          version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                                          build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown")
        }
    }
    private func poll() {
        guard enabled, !setupStep.isCapturing, !readInFlight else { return }
        // Permission and exact version/build are rechecked before every AX read.
        let trusted = AXIsProcessTrusted()
        guard trusted else { accessibilityTrusted = false; stopTimer(); retireSource(); reader.reset(); status = .accessibilityPermissionRequired; return }
        installedApplications = discoverApplications()
        guard let request = selectedRequest(), let profile = profiles.first(where: { $0.matches(request.application, provider: provider) }) else {
            retireSource(); status = profileVerified ? .sourceUnavailable : .profileVersionMismatch
            if !profileVerified { stopTimer() }
            return
        }
        let token = operationID
        readInFlight = true
        reader.read(request) { [weak self] result in
            MainActor.assumeIsolated {
                guard let self, self.operationID == token, self.enabled, !self.setupStep.isCapturing else { return }
                self.readInFlight = false
                guard case .observation(let observation) = result else {
                    self.retireSource(); self.status = .sourceUnavailable; return
                }
                // Reject updates observed after process termination/update or permission loss.
                guard AXIsProcessTrusted(), self.selectedRequest()?.application == request.application,
                      self.selectedRequest()?.processID == request.processID else {
                    self.retireSource(); self.status = .sourceUnavailable; return
                }
                guard observation.isOrdinaryChat else {
                    self.retireSource(); self.status = .ordinaryChatNotVerified; return
                }
                if self.sourceWindowID != observation.windowID || self.source?.processID != request.processID {
                    let source = AIActivitySource(provider: self.provider, processID: request.processID, sourceID: UUID())
                    self.source = source; self.sourceWindowID = observation.windowID; self.sequence = 0
                    self.tracker.selectSource(source); self.onSourceChanged?(source)
                }
                let phase = profile.phase(for: observation)
                self.status = phase == .unknown ? .sourceUnavailable : .monitoring
                guard let source = self.source else { return }
                self.sequence &+= 1
                if let snapshot = self.tracker.observe(source: source, phase: phase, at: observation.observedAt, sequence: self.sequence) {
                    self.onSnapshot?(snapshot)
                }
            }
        }
    }
    private func resetVerificationIfSourceLost() {
        guard setupStep.isCapturing else { return }
        verification = DesktopAIProfileVerification(); setupWindowID = nil; setupApplication = nil; setupStep = .captureIdle
    }
    private func retireSource() {
        if source != nil { source = nil; sourceWindowID = nil; tracker.selectSource(nil); sequence = 0; onSourceChanged?(nil) }
    }
    private func invalidateRead() { operationID = UUID(); readInFlight = false }
    private func stopTimer() { timer?.invalidate(); timer = nil }
    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshAvailability() }
            })
        }
    }
    deinit {
        timer?.invalidate()
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
    }
}
