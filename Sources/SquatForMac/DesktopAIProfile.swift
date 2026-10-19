import Foundation

enum AIConnectionSetupStep: String {
    case idle, captureIdle, captureRunning, captureCompletion, connected
    var isCapturing: Bool { self == .captureIdle || self == .captureRunning || self == .captureCompletion }
}

/// Only application metadata and a verified public button descriptor are persisted.
struct DesktopAIApplicationIdentity: Codable, Equatable {
    let bundleID: String
    let version: String
    let build: String

    static func bundleID(for provider: AIProvider) -> String {
        provider == .chatgptDesktop ? "com.openai.chat" : "com.anthropic.claudefordesktop"
    }
    var requiresChatModeProof: Bool { bundleID == "com.openai.codex" }
    func isSupported(for provider: AIProvider) -> Bool {
        (bundleID == Self.bundleID(for: provider) || (provider == .chatgptDesktop && bundleID == "com.openai.codex")) && !version.isEmpty && version != "unknown" && !build.isEmpty && build != "unknown"
    }
}

struct DesktopAIStopControl: Codable, Hashable {
    let role: String
    let identifier: String?
    let label: String

    static func normalizedLabel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    static let generationLabels: Set<String> = [
        "stop generating", "stop generating response", "stop response", "stop generating answer",
        "生成を停止", "応答の生成を停止", "回答の生成を停止", "応答を停止", "回答を停止"
    ]
    static let ambiguousLabels: Set<String> = [
        "stop", "停止", "中止", "cancel", "キャンセル", "allow", "allow once", "allow always",
        "approve", "approve once", "deny", "permission required", "continue", "続行", "許可", "承認", "拒否"
    ]
    // Dynamic IDs may include a URL, conversation ID or path. Keep only a
    // short fixed control identifier; all other controls use label-only matching.
    static let fixedStopIdentifiers: Set<String> = [
        "stop-generation", "stop-generating", "stop-response", "stop-button",
        "composer-stop-button", "stop-streaming-button", "chat-stop-generation", "chat-stop-button"
    ]
    static func safeIdentifier(_ value: String?) -> String? {
        guard let value, fixedStopIdentifiers.contains(value) else { return nil }
        return value
    }
    var isStrictGenerationControl: Bool {
        role == "AXButton" && Self.generationLabels.contains(Self.normalizedLabel(label))
            && (identifier.map({ Self.fixedStopIdentifiers.contains($0) }) ?? true)
    }
}

/// Mode labels are structural controls only. An integrated container needs
/// positive Chat selection plus explicit nonselection of its coding modes.
struct DesktopAIChatModeEvidence {
    static let chatLabels: Set<String> = ["chat", "チャット"]
    static let codingLabels: Set<String> = ["code", "cowork", "work", "codex", "コード", "ワーク"]
    private var selectedChat = false
    private var codingSeen = false
    private var conflictingOrUnknown = false
    static func recognizes(_ label: String) -> Bool { chatLabels.contains(label) || codingLabels.contains(label) }
    static let fixedModeIdentifiers: Set<String> = [
        "chat-tab", "code-tab", "work-tab", "cowork-tab", "codex-tab",
        "mode-chat", "mode-code", "mode-work", "mode-cowork", "mode-codex",
        "tab-chat", "tab-code", "tab-work", "tab-cowork", "tab-codex"
    ]
    mutating func observe(label: String, selected: Bool?, role: String = "AXTab", identifier: String? = nil) {
        let isModeControl = role == "AXTab" || role == "AXRadioButton"
            || (role == "AXButton" && identifier.map({ Self.fixedModeIdentifiers.contains($0) }) == true)
        if isModeControl, Self.chatLabels.contains(label), selected == true { selectedChat = true }
        if Self.codingLabels.contains(label) {
            codingSeen = true
            if !isModeControl || selected != false { conflictingOrUnknown = true }
        }
    }
    var verifiedOrdinaryChat: Bool { selectedChat && codingSeen && !conflictingOrUnknown }
    var hasConflictingOrUnknownMode: Bool { conflictingOrUnknown }
}

struct DesktopAIControlObservation {
    let application: DesktopAIApplicationIdentity
    let windowID: UUID
    let controls: [DesktopAIStopControl]
    let hasAmbiguousControl: Bool
    let complete: Bool
    let observedAt: TimeInterval
    let ordinaryChatModeVerified: Bool
    let hasConflictingMode: Bool

    init(application: DesktopAIApplicationIdentity, windowID: UUID, controls: [DesktopAIStopControl], hasAmbiguousControl: Bool, complete: Bool, observedAt: TimeInterval, ordinaryChatModeVerified: Bool = false, hasConflictingMode: Bool = false) {
        self.application = application; self.windowID = windowID; self.controls = controls
        self.hasAmbiguousControl = hasAmbiguousControl; self.complete = complete; self.observedAt = observedAt
        self.ordinaryChatModeVerified = ordinaryChatModeVerified; self.hasConflictingMode = hasConflictingMode
    }
    var isOrdinaryChat: Bool { !hasConflictingMode && (!application.requiresChatModeProof || ordinaryChatModeVerified) }
}

struct DesktopAIProfile: Codable, Equatable {
    let schemaVersion: Int
    let provider: AIProvider
    let application: DesktopAIApplicationIdentity
    let stopControl: DesktopAIStopControl

    init(provider: AIProvider, application: DesktopAIApplicationIdentity, stopControl: DesktopAIStopControl) {
        schemaVersion = 1
        self.provider = provider; self.application = application; self.stopControl = stopControl
    }
    var isValid: Bool {
        schemaVersion == 1 && application.isSupported(for: provider) && stopControl.isStrictGenerationControl
    }
    func matches(_ identity: DesktopAIApplicationIdentity, provider: AIProvider) -> Bool {
        isValid && self.provider == provider && application == identity
    }
    func phase(for observation: DesktopAIControlObservation) -> AIPhase {
        guard matches(observation.application, provider: provider), observation.complete,
              observation.observedAt.isFinite, observation.isOrdinaryChat, !observation.hasAmbiguousControl else { return .unknown }
        if observation.controls.isEmpty { return .idle }
        guard observation.controls.count == 1, observation.controls[0] == stopControl else { return .unknown }
        return .running
    }
}

/// A profile cannot be created from a label alone. The same window must show
/// no stop control, then exactly one new control, then its disappearance.
struct DesktopAIProfileVerification {
    private(set) var idle: DesktopAIControlObservation?
    private(set) var running: DesktopAIControlObservation?

    mutating func captureIdle(_ observation: DesktopAIControlObservation, provider: AIProvider) -> Bool {
        guard usable(observation, provider: provider), observation.controls.isEmpty else { return false }
        idle = observation; running = nil
        return true
    }
    mutating func captureRunning(_ observation: DesktopAIControlObservation, provider: AIProvider) -> Bool {
        guard let idle, sameSource(idle, observation), observation.observedAt > idle.observedAt,
              usable(observation, provider: provider), observation.controls.count == 1,
              observation.controls[0].isStrictGenerationControl else { return false }
        running = observation
        return true
    }
    func complete(_ observation: DesktopAIControlObservation, provider: AIProvider) -> DesktopAIProfile? {
        guard let running, sameSource(running, observation), observation.observedAt > running.observedAt,
              usable(observation, provider: provider), observation.controls.isEmpty else { return nil }
        let profile = DesktopAIProfile(provider: provider, application: observation.application, stopControl: running.controls[0])
        return profile.isValid ? profile : nil
    }
    private func usable(_ observation: DesktopAIControlObservation, provider: AIProvider) -> Bool {
        observation.application.isSupported(for: provider) && observation.isOrdinaryChat && observation.complete && observation.observedAt.isFinite
            && !observation.hasAmbiguousControl && observation.controls.allSatisfy(\.isStrictGenerationControl)
    }
    private func sameSource(_ a: DesktopAIControlObservation, _ b: DesktopAIControlObservation) -> Bool {
        a.application == b.application && a.windowID == b.windowID
    }
}
