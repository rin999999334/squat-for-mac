import Foundation

/// All synthetic data is confined to a preview bundle and its own preferences/DB.
@MainActor struct PreviewConfiguration {
    static let migratedStorageProfileKey = "SquatStorageProfile"

    let defaults: UserDefaults
    let databaseURL: URL?
    let fixedDate: Date?
    let fixture: String?

    static func make(preview: Bool, arguments: [String] = CommandLine.arguments) throws -> Self {
        let storageProfile = resolvedStorageProfile(
            bundleValue: Bundle.main.object(forInfoDictionaryKey: migratedStorageProfileKey) as? String,
            defaults: .standard
        )
        return try make(preview: preview, arguments: arguments, storageProfile: storageProfile)
    }

    static func resolvedStorageProfile(bundleValue: String?, defaults: UserDefaults) -> String? {
        bundleValue ?? defaults.string(forKey: migratedStorageProfileKey)
    }

    static func make(preview: Bool, arguments: [String], storageProfile: String?) throws -> Self {
        guard preview else {
            // A personal installation can retain a review user's real records without
            // shipping those records or a machine-specific path in a release bundle.
            guard let storageProfile else { return Self(defaults: .standard, databaseURL: nil, fixedDate: nil, fixture: nil) }
            guard let id = UUID(uuidString: storageProfile),
                  let defaults = UserDefaults(suiteName: "local.thinkandmove.qa.\(id.uuidString)") else { throw ConfigurationError.invalidProfile }
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
            let folder = support.appendingPathComponent("Squat for Mac/Profiles", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
            return Self(defaults: defaults, databaseURL: folder.appendingPathComponent("workout.sqlite"), fixedDate: nil, fixture: nil)
        }
        let suppliedFixture = arguments.first { $0.hasPrefix("--ui-fixture=") }.map { String($0.dropFirst(13)) }
        let profile = arguments.first { $0.hasPrefix("--qa-profile=") }.map { String($0.dropFirst(13)) }
            ?? (suppliedFixture == nil ? Bundle.main.object(forInfoDictionaryKey: "SquatReviewProfile") as? String : nil)
        if let profile {
            guard let id = UUID(uuidString: profile), suppliedFixture == nil else { throw ConfigurationError.invalidProfile }
            let name = "local.thinkandmove.qa.\(id.uuidString)"
            guard let defaults = UserDefaults(suiteName: name) else { throw ConfigurationError.preferences }
            let folder = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("qa/\(id.uuidString)", isDirectory: true)
            return Self(defaults: defaults, databaseURL: folder.appendingPathComponent("workout.sqlite"), fixedDate: nil, fixture: nil)
        }
        let fixture = suppliedFixture ?? "reference-weekly"
        guard ["reference-weekly", "reference-monthly", "fresh", "large", "refresh-reference"].contains(fixture) else { throw ConfigurationError.invalidFixture }
        let name = "local.thinkandmove.ui-preview.v27.preferences"
        guard let defaults = UserDefaults(suiteName: name) else { throw ConfigurationError.preferences }
        defaults.removePersistentDomain(forName: name)
        defaults.set("en", forKey: AppSettings.languageKey)
        defaults.set(true, forKey: AppSettings.simplifiedUIKey)
        if arguments.contains("--review-language=ja") { defaults.set("ja", forKey: AppSettings.languageKey) }
        defaults.set(arguments.contains("--welcome") ? false : true, forKey: AppSettings.onboardingKey)
        defaults.set(arguments.contains("--review-desk-on"), forKey: "squat.refresh.allowDesk")
        defaults.set(fixture == "fresh" ? 5 : fixture == "refresh-reference" ? 2 : 9, forKey: "sessionGoal")
        if fixture == "refresh-reference" {
            defaults.set(["chatgptDesktop", "claudeDesktop"], forKey: "squat.refresh.providers")
            defaults.set(true, forKey: "squat.refresh.allowAI")
            defaults.set(true, forKey: "squat.refresh.allowDesk")
            defaults.set(true, forKey: AppSettings.usageKey)
            defaults.set(120, forKey: AppSettings.usageIntervalKey)
        }
        if let interval = arguments.first(where: { $0.hasPrefix("--review-interval=") }).flatMap({ Int($0.dropFirst(18)) }) {
            defaults.set(UsageReminderInterval.normalized(interval).rawValue, forKey: AppSettings.usageIntervalKey)
        }
        let calendar = ProgressCalendarModel.localCalendar()
        let today = calendar.date(from: DateComponents(year: 2026, month: fixture == "refresh-reference" ? 2 : 10, day: fixture == "refresh-reference" ? 21 : 15, hour: 12))!
        if fixture != "fresh" && fixture != "refresh-reference" { try seed(defaults, fixture: fixture, today: today, calendar: calendar) }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SquatPreview-\(UUID().uuidString)", isDirectory: true)
        return Self(defaults: defaults, databaseURL: folder.appendingPathComponent("workout.sqlite"), fixedDate: today, fixture: fixture)
    }

    private struct Event: Encodable { let sessionID: UUID; let recordedAt: Date }
    private struct Archive: Encodable {
        let version = 1
        let sessions: [WorkoutSession]
        let events: [Event]
        let activeSessionID: UUID? = nil
        let legacyTotal = 0
    }
    private static func seed(_ defaults: UserDefaults, fixture: String, today: Date, calendar: Calendar) throws {
        var sessions: [WorkoutSession] = [], events: [Event] = []
        let start = calendar.date(byAdding: .day, value: fixture == "large" ? -364 : -18, to: today)!
        let dayCount = fixture == "large" ? 365 : 19
        for index in 0..<dayCount {
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            let count = fixture == "large" ? (index < 360 ? 137 : 136) : [1, 10, 20, 25, 30, 0, 0][index % 7]
            guard count > 0 else { continue }
            let id = UUID()
            sessions.append(WorkoutSession(id: id, startedAt: date, endedAt: date, reps: count, mode: "face", completed: true))
            events.append(contentsOf: (0..<count).map { _ in Event(sessionID: id, recordedAt: date) })
        }
        defaults.set(try JSONEncoder().encode(Archive(sessions: sessions, events: events)), forKey: "thinkAndMove.workoutHistory.v1")
    }
    enum ConfigurationError: Error { case invalidProfile, invalidFixture, preferences }
}
