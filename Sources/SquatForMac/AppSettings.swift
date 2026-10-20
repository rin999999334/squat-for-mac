import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, en
    var id: String { rawValue }
}

@MainActor final class AppSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Self.onboardingKey) } }
    @Published var language: AppLanguage { didSet { defaults.set(language.rawValue, forKey: Self.languageKey) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) } }
    @Published var aiEnabled: Bool { didSet { defaults.set(aiEnabled, forKey: Self.aiKey) } }
    @Published var aiProvider: AIProvider { didSet { defaults.set(aiProvider.rawValue, forKey: Self.aiProviderKey) } }
    @Published var breakRemindersEnabled: Bool { didSet { defaults.set(breakRemindersEnabled, forKey: Self.breakRemindersKey) } }
    @Published var usageRemindersEnabled: Bool { didSet { defaults.set(usageRemindersEnabled, forKey: Self.usageKey) } }
    @Published var usageReminderInterval: UsageReminderInterval { didSet { defaults.set(usageReminderInterval.rawValue, forKey: Self.usageIntervalKey) } }
    @Published var selectedProviders: Set<AIProvider> { didSet { defaults.set(selectedProviders.map(\.rawValue).sorted(), forKey: "squat.refresh.providers") } }
    @Published var usageCollectionAllowed: Bool { didSet { defaults.set(usageCollectionAllowed, forKey: "squat.refresh.allowAI") } }
    @Published var deskCollectionAllowed: Bool { didSet { defaults.set(deskCollectionAllowed, forKey: "squat.refresh.allowDesk") } }
    @Published var publicShareURL: String { didSet { defaults.set(publicShareURL, forKey: "squat.shareURL") } }
    var shareURL: URL? { RefreshExternalLinks.githubURL(publicShareURL) }
    var isDemoShareURL: Bool { shareURL?.absoluteString == RefreshExternalLinks.demoShare }
    var contactFormURL: URL? { configuredURL("squat.contactURL", host: nil) ?? RefreshExternalLinks.contact }
    private func configuredURL(_ key: String, host: String?) -> URL? {
        guard let value = defaults.string(forKey: key), let u = URL(string: value), u.scheme == "https",
              let h = u.host, host.map({ h == $0 }) ?? (h == "forms.gle" || h == "docs.google.com") else { return nil }
        return u
    }
    static let usageKey = "thinkAndMove.reminders.usage.enabled.v1"
    static let usageIntervalKey = "thinkAndMove.reminders.usage.intervalMinutes.v1"
    static let simplifiedUIKey = "thinkAndMove.ui.simplified.v1"
    static let onboardingKey = "thinkAndMove.ui.onboardingCompleted.v1"
    static let languageKey = "thinkAndMove.ui.language.v1"
    static let hapticsKey = "thinkAndMove.ui.hapticsEnabled.v1"
    static let aiKey = "thinkAndMove.ai.enabled.v1"
    static let aiProviderKey = "thinkAndMove.ai.provider.v1"
    static let breakRemindersKey = "thinkAndMove.reminders.break.enabled.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedShare = defaults.string(forKey: "squat.shareURL") ?? RefreshExternalLinks.defaultShare
        publicShareURL = storedShare == RefreshExternalLinks.demoShare ? RefreshExternalLinks.defaultShare : storedShare
        if !defaults.bool(forKey: Self.simplifiedUIKey) {
            if defaults.string(forKey: Self.languageKey) == nil { defaults.set(AppLanguage.system.rawValue, forKey: Self.languageKey) }
            defaults.set(true, forKey: "looseMode")
            defaults.set(false, forKey: Self.breakRemindersKey)
            defaults.set(true, forKey: Self.simplifiedUIKey)
        }
        usageRemindersEnabled = defaults.bool(forKey: Self.usageKey)
        let initialInterval: UsageReminderInterval = defaults.object(forKey: Self.usageIntervalKey) == nil ? .minutes60 : UsageReminderInterval.normalized(defaults.integer(forKey: Self.usageIntervalKey))
        usageReminderInterval = initialInterval
        defaults.set(initialInterval.rawValue, forKey: Self.usageIntervalKey)
        onboardingCompleted = defaults.bool(forKey: Self.onboardingKey)
        language = AppLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "") ?? .system
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) == nil ? true : defaults.bool(forKey: Self.hapticsKey)
        aiEnabled = defaults.bool(forKey: Self.aiKey)
        aiProvider = AIProvider(rawValue: defaults.string(forKey: Self.aiProviderKey) ?? "") ?? .chatgptDesktop
        breakRemindersEnabled = defaults.bool(forKey: Self.breakRemindersKey)
        if let values = defaults.stringArray(forKey: "squat.refresh.providers") {
            selectedProviders = Set(values.compactMap(AIProvider.init(rawValue:)))
        } else if let old = defaults.string(forKey: Self.aiProviderKey).flatMap(AIProvider.init(rawValue:)) {
            selectedProviders = [old]
        } else if defaults.bool(forKey: Self.usageKey) {
            // The previous app's saved ON state used ChatGPT when no provider key was written.
            selectedProviders = [.chatgptDesktop]
        } else { selectedProviders = [] }
        usageCollectionAllowed = defaults.object(forKey: "squat.refresh.allowAI") as? Bool ?? defaults.bool(forKey: Self.usageKey)
        deskCollectionAllowed = defaults.bool(forKey: "squat.refresh.allowDesk")
        // Versions that experimented with Codex hooks may have left these
        // preferences behind. Time-based reminders are now the only mode.
        defaults.removeObject(forKey: "squat.refresh.trigger")
        defaults.removeObject(forKey: "squat.refresh.link")
        if !defaults.bool(forKey: "squat.refresh.migrated.v25") {
            language = Self.resolvedLanguage(language, preferredLanguages: Locale.preferredLanguages)
            defaults.set(language.rawValue, forKey: Self.languageKey)
            defaults.set(true, forKey: Self.onboardingKey)
            onboardingCompleted = true
            defaults.set(true, forKey: "squat.refresh.migrated.v25")
        }
    }
    var isJapanese: Bool {
        Self.resolvedLanguage(language, preferredLanguages: Locale.preferredLanguages) == .ja
    }
    static func resolvedLanguage(_ selection: AppLanguage, preferredLanguages: [String]) -> AppLanguage {
        guard selection == .system else { return selection }
        for identifier in preferredLanguages {
            let code = identifier.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first
            if code == "ja" { return .ja }
            if code == "en" { return .en }
        }
        return .en
    }
    var locale: Locale { Locale(identifier: isJapanese ? "ja_JP" : "en_US") }
    func t(_ ja: String, _ en: String) -> String { isJapanese ? ja : en }
}
