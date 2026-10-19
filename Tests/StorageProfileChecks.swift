import Foundation

@main struct StorageProfileChecks {
    @MainActor static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            guard value() else { fatalError(message) }; count += 1
        }
        let normal = try PreviewConfiguration.make(preview: false,
            arguments: ["test", "--ui-fixture=refresh-reference", "--qa-profile=not-a-uuid"], storageProfile: nil)
        check(normal.defaults === UserDefaults.standard, "Normal build uses ordinary defaults")
        check(normal.databaseURL == nil && normal.fixture == nil && normal.fixedDate == nil, "Review arguments cannot seed a normal build")
        let id = UUID()
        let personal = try PreviewConfiguration.make(preview: false, arguments: ["test", "--ui-fixture=fresh"], storageProfile: id.uuidString.lowercased())
        check(personal.defaults !== UserDefaults.standard, "Personal profile has isolated preferences")
        check(personal.databaseURL?.lastPathComponent == "workout.sqlite", "Profile database name is stable")
        check(personal.databaseURL?.deletingLastPathComponent().lastPathComponent == id.uuidString, "Only canonical UUID enters profile path")
        check(personal.databaseURL?.path.contains("Application Support/Squat for Mac/Profiles/") == true, "Desktop installation is independent of app location")
        check(personal.fixture == nil && personal.fixedDate == nil, "Personal build uses real time and no fixture")
        for invalid in ["", "../other-user", "/tmp/other", "not-a-uuid"] {
            do {
                _ = try PreviewConfiguration.make(preview: false, arguments: ["test"], storageProfile: invalid)
                fatalError("Invalid profile accepted")
            } catch PreviewConfiguration.ConfigurationError.invalidProfile { count += 1 }
        }
        print("PASS: \(count) storage profile checks")
    }
}
