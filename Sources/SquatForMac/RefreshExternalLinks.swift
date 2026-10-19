import Foundation

enum RefreshExternalLinks {
    static let contact = URL(string: "https://forms.gle/1ZvABbbDHBRJsd529")!
    static let demoShare = "https://github.com/example/squat"
    static let defaultShare = "https://github.com/rin999999334/squat-for-mac"
    static func githubURL(_ value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parts = URLComponents(string: text), parts.scheme == "https",
              parts.host?.lowercased() == "github.com", parts.user == nil, parts.password == nil,
              parts.port == nil, parts.query == nil, parts.fragment == nil,
              parts.path.split(separator: "/").count >= 2 else { return nil }
        return parts.url
    }
}

enum RefreshSocialDestination: String, CaseIterable, Identifiable {
    case x, instagram
    var id: String { rawValue }
    var title: String { self == .x ? "X" : "Instagram" }
    func composeURL(github: URL) -> URL {
        guard self == .x else { return URL(string: "https://www.instagram.com/")! }
        var parts = URLComponents(string: "https://x.com/intent/tweet")!
        parts.queryItems = [URLQueryItem(name: "url", value: github.absoluteString)]
        return parts.url!
    }
}
