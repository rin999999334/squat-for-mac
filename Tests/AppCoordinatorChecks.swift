import Foundation

@main enum AppCoordinatorChecks {
    @MainActor static func main() async {
        let suite = "Squat.CoordinatorChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            precondition(condition(), label); checked += 1
        }
        let settings = AppSettings(defaults: defaults)
        let store = MoveStore(defaults: defaults)
        let coordinator = AppCoordinator(store: store, settings: settings)
        check(store.goal == 5, "New installs start at five")
        check(coordinator.screen == .home && !store.active, "First launch opens Home without camera")
        check(!settings.aiEnabled && settings.hapticsEnabled, "Initial preferences")
        check(settings.language == .ja || settings.language == .en, "Language resolves and is saved at first launch")
        check(settings.usageReminderInterval == .minutes60, "Reminder time defaults to 60 minutes")
        for interval in UsageReminderInterval.allCases {
            settings.usageReminderInterval = interval
            check(AppSettings(defaults: defaults).usageReminderInterval == interval, "Reminder time survives reload: \(interval.rawValue)")
        }
        defaults.set(45, forKey: AppSettings.usageIntervalKey)
        check(AppSettings(defaults: defaults).usageReminderInterval == .minutes30, "Invalid reminder time snaps to closest value with lower tie per v2.7")
        settings.usageReminderInterval = .minutes60
        check(AppSettings.resolvedLanguage(.system, preferredLanguages: ["ja-JP", "en-US"]) == .ja, "System Japanese is selected")
        check(AppSettings.resolvedLanguage(.system, preferredLanguages: ["en-US", "ja-JP"]) == .en, "System English is selected")
        check(AppSettings.resolvedLanguage(.system, preferredLanguages: ["fr-FR", "ja_JP"]) == .ja, "The first supported system language is selected")
        check(AppSettings.resolvedLanguage(.system, preferredLanguages: ["fr-FR"]) == .en, "Unsupported system languages fall back to English")
        check(AppSettings.resolvedLanguage(.ja, preferredLanguages: ["en-US"]) == .ja, "Explicit Japanese remains available")
        check(AppSettings.resolvedLanguage(.en, preferredLanguages: ["ja-JP"]) == .en, "Explicit English remains available")
        settings.language = .ja
        check(settings.t("日本語", "English") == "日本語", "Japanese selection")
        settings.language = .en
        check(settings.t("日本語", "English") == "English", "English selection")
        settings.hapticsEnabled = false
        let restoredSettings = AppSettings(defaults: defaults)
        check(restoredSettings.language == .en && !restoredSettings.hapticsEnabled, "Preferences survive reload")
        check(!settings.usageCollectionAllowed && !settings.deskCollectionAllowed && !settings.pluginLinkEnabled, "Collection and integration start without consent")
        settings.selectedProviders = [.chatgptDesktop, .claudeDesktop]
        settings.soundVolume = 50
        settings.usageCollectionAllowed = true
        settings.deskCollectionAllowed = true
        let reviewSettings = AppSettings(defaults: defaults)
        check(reviewSettings.selectedProviders == [.chatgptDesktop, .claudeDesktop], "Both providers persist independently")
        check(reviewSettings.soundVolume == 50 && reviewSettings.usageCollectionAllowed && reviewSettings.deskCollectionAllowed, "Sound and collection settings persist")
        settings.selectedProviders.remove(.claudeDesktop)
        check(AppSettings(defaults: defaults).selectedProviders == [.chatgptDesktop], "Turning one provider off preserves the other")
        check(settings.reminderTriggerMode == .time && !settings.pluginLinkEnabled, "Installing no plugin keeps time mode")
        coordinator.openSettings()
        check(coordinator.screen == .settings && coordinator.showSettings, "Settings is available without onboarding")
        coordinator.completeOnboarding()
        check(coordinator.screen == .home && settings.onboardingCompleted, "Skip completes onboarding")
        coordinator.openSettings()
        check(coordinator.screen == .settings && coordinator.showSettings, "Settings uses its own page")
        check(coordinator.screen.allowsUsageReminder, "Leaving Settings in the background permits usage invitations")
        coordinator.goHome()
        check(coordinator.screen == .home && !coordinator.showSettings, "Back leaves Settings")
        coordinator.openHistory(); coordinator.openSettings(); coordinator.closeSettings()
        check(coordinator.screen == .home, "Settings Home always returns to Home")
        coordinator.goHome()
        store.goal = 17; store.saveSettings()
        let restored = MoveStore(defaults: defaults)
        check(restored.goal == 17, "Existing target remains")
        coordinator.start(tutorial: true, demo: true)
        coordinator.openSettings()
        check(coordinator.screen == .prepare && !coordinator.showSettings, "Settings cannot interrupt measurement")
        check(!coordinator.screen.allowsUsageReminder, "Camera preparation still suppresses usage invitations")
        let firstID = store.sessionID
        check(store.active && store.sessionTarget == 5 && store.goal == 17, "Tutorial uses five without overwriting preference")
        check(defaults.integer(forKey: "sessionGoal") == 17, "Saved normal target remains")
        coordinator.start(demo: true)
        check(store.sessionID == firstID, "Repeated Start does not start a second session")
        coordinator.finish()
        check(!store.active && coordinator.screen == .home && coordinator.result == nil, "Preparation cancellation returns Home")
        coordinator.start(demo: true)
        store.count = 3; store.startedAt = Date().addingTimeInterval(-2)
        coordinator.finish()
        check(coordinator.screen == .result && coordinator.result?.count == 3, "Partial session has a result")
        check(coordinator.result?.target == 17 && coordinator.result?.isDemo == true && coordinator.result?.completed == false, "Result keeps session snapshot")
        let result = coordinator.result
        coordinator.finish()
        check(coordinator.result == result, "Finish is idempotent")
        check(store.history.lifetimeReps == 0, "Demo never enters real history")
        coordinator.goHome()
        check(coordinator.screen == .home && coordinator.result == nil && !store.active, "Reopen resets to Home")
        coordinator.start(demo: true)
        coordinator.goHome()
        check(!store.active && coordinator.screen == .home, "Opening Home stops active measurement")
        coordinator.start(demo: true)
        store.preparing = false
        coordinator.goHome()
        coordinator.start(demo: true)
        try? await Task.sleep(nanoseconds: 30_000_000)
        check(coordinator.screen == .prepare && store.preparing, "Stale preparation events cannot advance a new run")
        coordinator.goHome()
        defaults.set(90, forKey: "sessionGoal")
        check(MoveStore(defaults: defaults).goal == 30, "Invalid high target clamped")
        defaults.set(-5, forKey: "sessionGoal")
        check(MoveStore(defaults: defaults).goal == 1, "Invalid low target clamped")
        coordinator.start(demo: true, target: 9)
        check(store.sessionTarget == 9 && store.goal == 17, "An accepted invitation uses its captured target without changing the normal goal")
        store.count = 3
        store.adjustSessionTarget(by: 1)
        check(store.sessionTarget == 10 && store.goal == 17, "Current target updates without changing next goal")
        for _ in 0..<20 { store.adjustSessionTarget(by: -1) }
        check(store.sessionTarget == 4 && store.count == 3 && store.active, "Minus cannot end a session by lowering to count")
        for _ in 0..<60 { store.adjustSessionTarget(by: 1) }
        check(store.sessionTarget == 30, "Current target remains at most thirty")
        let id = store.sessionID
        store.recalibrate()
        check(store.count == 3 && store.sessionTarget == 30 && store.sessionID == id, "Recalibration preserves count, target and identity")
        coordinator.goHome()
        store.adjustSessionTarget(by: -1)
        check(store.sessionTarget == 30, "An inactive session cannot change target")
        coordinator.start(demo: true,target: 30)
        store.demo = false; store.count = 1; store.startedAt = Date()
        store.history.beginSession(mode: "face",at: store.history.currentDate)
        store.history.recordRep(at: store.history.currentDate,mode: "face")
        coordinator.goHome()
        check(coordinator.screen == .home && !store.active && store.history.todayReps == 1, "One actual recorded rep survives Home before reaching target")
        check(store.history.activeDayCount == 1 && store.history.count(on: Calendar.current.startOfDay(for: store.history.currentDate)) == 1, "A partial workout marks the day active")
        check(!settings.breakRemindersEnabled && settings.aiProvider == .chatgptDesktop,
              "Break reminders stay opt-in and the selected provider has an explicit default")
        let migrationSuite = suite + ".migration"
        let legacy = UserDefaults(suiteName: migrationSuite)!
        defer { legacy.removePersistentDomain(forName: migrationSuite) }
        legacy.set("ja", forKey: AppSettings.languageKey); legacy.set(false, forKey: "looseMode")
        legacy.set(true, forKey: AppSettings.breakRemindersKey); legacy.set(true, forKey: AppSettings.aiKey)
        legacy.set("claudeDesktop", forKey: AppSettings.aiProviderKey)
        legacy.set(17, forKey: "sessionGoal"); legacy.set(123, forKey: "totalReps")
        let migrated = AppSettings(defaults: legacy)
        check(migrated.language == .ja && legacy.bool(forKey: "looseMode") && !migrated.breakRemindersEnabled, "Migration preserves explicit language")
        check(!migrated.usageRemindersEnabled && migrated.aiEnabled, "Old AI permission is never consent to usage tracking")
        check(migrated.aiProvider == .claudeDesktop && legacy.integer(forKey: "sessionGoal") == 17 && legacy.integer(forKey: "totalReps") == 123, "Migration preserves provider, target and history")
        let defaultSuite = suite + ".legacy-default-provider"
        let defaultProvider = UserDefaults(suiteName: defaultSuite)!
        defer { defaultProvider.removePersistentDomain(forName: defaultSuite) }
        defaultProvider.set(true,forKey: AppSettings.usageKey)
        let inherited = AppSettings(defaults: defaultProvider)
        check(inherited.selectedProviders == [.chatgptDesktop] && inherited.usageCollectionAllowed, "Legacy reminders ON retains its documented default provider without selecting Claude")
        print("PASS: \(checked) coordinator/settings checks")
    }
}
