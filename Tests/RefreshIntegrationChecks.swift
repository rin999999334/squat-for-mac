import Foundation

@main enum RefreshIntegrationChecks {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () throws -> Bool, _ message: String) {
            count += 1; precondition(try! value(), message)
        }
        check(RefreshExternalLinks.githubURL(RefreshExternalLinks.demoShare) != nil, "Demo is an explicit repository-shaped URL")
        let valid = "https://github.com/rin/Squat"
        check(RefreshExternalLinks.githubURL(" \n" + valid + " ")?.absoluteString == valid, "Trim user input")
        for invalid in ["http://github.com/rin/Squat", "https://github.com", "https://github.com/rin", "https://github.com.evil.test/rin/Squat", "https://user@github.com/rin/Squat", "https://github.com:8443/rin/Squat", "javascript:alert(1)", "https://github.com/rin/Squat?token=secret", "https://github.com/rin/Squat#private"] {
            check(RefreshExternalLinks.githubURL(invalid) == nil, "Reject malformed or nonpublic repository URL")
        }
        let name = "local.thinkandmove.integration-checks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        check(settings.contactFormURL == RefreshExternalLinks.contact, "Contact button has the supplied default destination")
        check(settings.shareURL?.absoluteString == RefreshExternalLinks.defaultShare && !settings.isDemoShareURL, "Fresh installs share the real public repository")
        defaults.set(RefreshExternalLinks.demoShare, forKey: "squat.shareURL")
        let migrated = AppSettings(defaults: defaults)
        check(migrated.shareURL?.absoluteString == RefreshExternalLinks.defaultShare && !migrated.isDemoShareURL, "Only the legacy placeholder migrates to the public repository")
        settings.publicShareURL = valid
        let restored = AppSettings(defaults: defaults)
        check(restored.shareURL?.absoluteString == valid && !restored.isDemoShareURL, "Custom URL survives reopening settings")
        check(!restored.pluginLinkEnabled && restored.reminderTriggerMode == .time, "Changing URL doesn't enable hooks or switch reminder mode")
        defaults.set("https://malicious.test/", forKey: "squat.contactURL")
        check(AppSettings(defaults: defaults).contactFormURL == RefreshExternalLinks.contact, "Invalid override cannot redirect Contact us")
        let components = URLComponents(url: RefreshSocialDestination.x.composeURL(github: URL(string: valid)!), resolvingAgainstBaseURL: false)!
        check(components.host == "x.com" && components.path == "/intent/tweet", "Open an X composer, not a publication endpoint")
        check(components.queryItems == [URLQueryItem(name: "url", value: valid)], "Only the GitHub URL is prefilled, no marketing copy")
        check(RefreshSocialDestination.instagram.composeURL(github: URL(string: valid)!).absoluteString == "https://www.instagram.com/", "Instagram doesn't pretend to support local attachment URLs")
        func snapshot(_ entries: [[String: Any]], available: [[String: Any]] = [], exit: Int32 = 0) throws -> RefreshPluginInstallation {
            RefreshPluginInstallation.parse(try JSONSerialization.data(withJSONObject: ["installed": entries, "available": available]), exitCode: exit)
        }
        let target: [String: Any] = ["pluginId": RefreshPluginInstallation.pluginID, "installed": true, "enabled": true, "version": "0.0.2"]
        check(try snapshot([]).state == .notInstalled, "Empty authoritative installed list means absent")
        check(try snapshot([], available: [target]).state == .notInstalled, "Marketplace/cache presence isn't installation")
        check(try snapshot([target]).state == .installed, "Exact installed identity is detected")
        check(try snapshot([target]).version == "0.0.2", "Installed version is preserved")
        var disabled = target; disabled["enabled"] = false
        check(try snapshot([disabled]).state == .disabled, "Disabled is separate from absent")
        var missing = target; missing.removeValue(forKey: "enabled")
        check(try snapshot([missing]).state == .unknown, "Incomplete metadata isn't guessed")
        check(try snapshot([target], exit: 1).state == .unknown, "Failed command can't prove absence")
        check(RefreshPluginInstallation.parse(Data("{}".utf8), exitCode: 0).state == .unknown, "Missing inventory is unknown")
        check(RefreshPluginInstallation.parse(Data("error".utf8), exitCode: 0).state == .unknown, "Invalid JSON is unknown")
        var other = target; other["pluginId"] = "squat-link-review@another-marketplace"
        check(try snapshot([other]).state == .notInstalled, "Do not confuse a similarly named plugin")
        check(try snapshot([target, target]).state == .unknown, "Conflicting records are not reported as connected")
        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("squat-inventory-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }
        func run(_ script: String, timeout: TimeInterval = 2) throws -> RefreshPluginInstallation {
            let path = fixture.appendingPathComponent(UUID().uuidString + ".sh")
            try script.write(to: path, atomically: true, encoding: .utf8)
            return RefreshPluginInventory.read(executable: URL(fileURLWithPath: "/bin/sh"), arguments: [path.path], timeout: timeout)
        }
        check(try run("printf '%s' '{\"installed\":[]}'").state == .notInstalled, "Real subprocess captures valid inventory")
        check(try run("printf '%s' '{\"installed\":[]}'; exit 2").state == .unknown, "Real subprocess exit failure isn't absence")
        let started = ProcessInfo.processInfo.systemUptime
        check(try run("while :; do :; done", timeout: 0.1).state == .unknown, "Hung inventory check times out")
        check(ProcessInfo.processInfo.systemUptime - started < 2, "Timeout returns promptly")
        check(try run("/usr/bin/yes x | /usr/bin/head -c 300000").state == .unknown, "Large output is bounded and rejected")
        print("PASS: \(count) external-link, persistence and plugin-discovery checks")
    }
}
