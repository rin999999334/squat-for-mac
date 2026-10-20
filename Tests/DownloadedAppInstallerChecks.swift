import Foundation

@main @MainActor struct DownloadedAppInstallerChecks {
    static func main() {
        var passed = 0
        func check(_ value: @autoclosure () -> Bool, _ label: String) {
            guard value() else { fputs("FAIL: \(label)\n", stderr); exit(1) }
            passed += 1
        }
        let downloaded = URL(fileURLWithPath: "/Users/test/Downloads/Squat for Mac.app")
        let installed = URL(fileURLWithPath: "/Applications/Squat for Mac.app")
        check(DownloadedAppInstallPolicy.action(sourceURL: installed, targetURL: installed, sourceVersion: "0.9.3", installedVersion: "0.9.2", targetExists: true) == .none,
              "Running the installed copy never offers to replace itself")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "0.9.3", installedVersion: nil, targetExists: false) == .install,
              "A downloaded copy offers installation when no installed app exists")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "0.9.3", installedVersion: "0.9.2", targetExists: true) == .replace,
              "A newer downloaded version offers replacement")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "0.9.3", installedVersion: "0.9.3", targetExists: true) == .none,
              "The same version is not replaced repeatedly")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "0.9.2", installedVersion: "0.9.3", targetExists: true) == .none,
              "An older download cannot downgrade the installed app")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "0.9.10", installedVersion: "0.9.9", targetExists: true) == .replace,
              "Version comparison is numeric")
        check(DownloadedAppInstallPolicy.action(sourceURL: downloaded, targetURL: installed, sourceVersion: "1.0.0", installedVersion: nil, targetExists: true) == .replace,
              "An unreadable installed version can be replaced after validation")
        let inheritedID = UUID()
        check(DownloadedAppStorageMigration.profile(fromBundleInfo: [DownloadedAppStorageMigration.profileKey: inheritedID.uuidString.lowercased()]) == inheritedID.uuidString,
              "A legacy storage profile is normalized for migration")
        check(DownloadedAppStorageMigration.profile(fromBundleInfo: [DownloadedAppStorageMigration.profileKey: "../other-user"]) == nil,
              "An invalid legacy storage profile is never migrated")
        check(DownloadedAppStorageMigration.profile(fromBundleInfo: nil) == nil,
              "A generic installed app has no legacy profile to migrate")

        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("squat-installer-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        do {
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            func app(_ name: String, marker: String) throws -> URL {
                let url = root.appendingPathComponent(name, isDirectory: true)
                try manager.createDirectory(at: url, withIntermediateDirectories: true)
                try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
                return url
            }
            func marker(_ url: URL) throws -> String {
                try String(contentsOf: url.appendingPathComponent("marker"), encoding: .utf8)
            }
            let firstSource = try app("downloaded-first.app", marker: "new")
            let firstTarget = root.appendingPathComponent("Applications/first.app", isDirectory: true)
            try manager.createDirectory(at: firstTarget.deletingLastPathComponent(), withIntermediateDirectories: true)
            var replacementPreparationCount = 0
            try DownloadedAppBundleReplacement.install(source: firstSource, target: firstTarget,
                                                        beforeReplacing: { replacementPreparationCount += 1 }) {
                guard try marker($0) == "new" else { throw TestError.invalid }
            }
            let firstInstalledMarker = try marker(firstTarget)
            check(firstInstalledMarker == "new", "A downloaded app can be installed into an empty destination")
            check(replacementPreparationCount == 0, "A first installation does not stop another app")

            let updateSource = try app("downloaded-update.app", marker: "newer")
            let updateTarget = try app("Applications/update.app", marker: "older")
            try DownloadedAppBundleReplacement.install(source: updateSource, target: updateTarget,
                                                        beforeReplacing: { replacementPreparationCount += 1 }) {
                guard try marker($0) == "newer" else { throw TestError.invalid }
            }
            let updatedMarker = try marker(updateTarget)
            let applicationItems = try manager.contentsOfDirectory(atPath: firstTarget.deletingLastPathComponent().path)
            check(updatedMarker == "newer", "A downloaded app replaces the old bundle")
            check(replacementPreparationCount == 1, "The old app is stopped only after staging succeeds")
            check(applicationItems.allSatisfy { !$0.contains("backup") && !$0.contains("install-") },
                  "Successful installation removes staging artifacts")

            let failedSource = try app("downloaded-failed.app", marker: "candidate")
            let failedTarget = try app("Applications/failed.app", marker: "preserved")
            do {
                try DownloadedAppBundleReplacement.install(source: failedSource, target: failedTarget) {
                    if $0.standardizedFileURL == failedTarget.standardizedFileURL { throw TestError.invalid }
                }
                check(false, "Final validation failure must be reported")
            } catch {
                let restoredMarker = try marker(failedTarget)
                check(restoredMarker == "preserved", "A failed final validation restores the old app")
            }

            let realTarget = try app("Applications/real.app", marker: "preserved")
            let linkedTarget = root.appendingPathComponent("Applications/linked.app")
            try manager.createSymbolicLink(at: linkedTarget, withDestinationURL: realTarget)
            do {
                try DownloadedAppBundleReplacement.install(source: updateSource, target: linkedTarget) { _ in }
                check(false, "A linked replacement target must be rejected")
            } catch {
                let preservedMarker = try marker(realTarget)
                check(preservedMarker == "preserved", "Rejecting a linked target leaves its destination untouched")
            }
        } catch {
            fputs("FAIL: installer file-operation setup: \(error)\n", stderr)
            exit(1)
        }

        if let fixturePath = ProcessInfo.processInfo.environment["SQUAT_SIGNED_APP_FIXTURE"] {
            let fixture = URL(fileURLWithPath: fixturePath, isDirectory: true)
            let signedRoot = manager.temporaryDirectory.appendingPathComponent("squat-signed-installer-check-\(UUID().uuidString)", isDirectory: true)
            defer { try? manager.removeItem(at: signedRoot) }
            do {
                guard let version = Bundle(url: fixture)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { throw TestError.invalid }
                try manager.createDirectory(at: signedRoot, withIntermediateDirectories: true)
                let target = signedRoot.appendingPathComponent("Squat for Mac.app", isDirectory: true)
                try manager.copyItem(at: fixture, to: target)
                var prepared = false
                try DownloadedAppBundleReplacement.install(source: fixture, target: target,
                                                            beforeReplacing: { prepared = true }) {
                    try DownloadedAppInstaller.validateBundle(at: $0, expectedVersion: version)
                }
                try DownloadedAppInstaller.validateBundle(at: target, expectedVersion: version)
                check(prepared, "A signed app replacement prepares the existing copy")
                check(manager.fileExists(atPath: target.path), "A real signed app remains valid after replacement")
            } catch {
                fputs("FAIL: signed app replacement: \(error)\n", stderr)
                exit(1)
            }
        }
        print("PASS: \(passed) downloaded-app installer policy checks")
    }

    enum TestError: Error { case invalid }
}
