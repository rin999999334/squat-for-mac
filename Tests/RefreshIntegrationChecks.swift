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
        check(defaults.object(forKey: "squat.refresh.trigger") == nil && defaults.object(forKey: "squat.refresh.link") == nil, "Changing URL doesn't restore removed integration preferences")
        defaults.set("https://malicious.test/", forKey: "squat.contactURL")
        check(AppSettings(defaults: defaults).contactFormURL == RefreshExternalLinks.contact, "Invalid override cannot redirect Contact us")
        let components = URLComponents(url: RefreshSocialDestination.x.composeURL(github: URL(string: valid)!), resolvingAgainstBaseURL: false)!
        check(components.host == "x.com" && components.path == "/intent/tweet", "Open an X composer, not a publication endpoint")
        check(components.queryItems == [URLQueryItem(name: "url", value: valid)], "Only the GitHub URL is prefilled, no marketing copy")
        check(RefreshSocialDestination.instagram.composeURL(github: URL(string: valid)!).absoluteString == "https://www.instagram.com/", "Instagram doesn't pretend to support local attachment URLs")
        print("PASS: \(count) external-link and persistence checks")
    }
}
