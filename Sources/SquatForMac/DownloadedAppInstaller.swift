import AppKit
import Foundation
import Security

enum DownloadedAppInstallAction: Equatable {
    case none
    case install
    case replace
}

enum DownloadedAppInstallPolicy {
    static func action(sourceURL: URL, targetURL: URL, sourceVersion: String,
                       installedVersion: String?, targetExists: Bool) -> DownloadedAppInstallAction {
        if sourceURL.standardizedFileURL == targetURL.standardizedFileURL { return .none }
        guard targetExists else { return .install }
        guard let installedVersion else { return .replace }
        return sourceVersion.compare(installedVersion, options: [.numeric, .caseInsensitive]) == .orderedDescending ? .replace : .none
    }
}

enum DownloadedAppStorageMigration {
    static let profileKey = "SquatStorageProfile"

    static func profile(fromBundleInfo info: [String: Any]?) -> String? {
        guard let value = info?[profileKey] as? String,
              let id = UUID(uuidString: value) else { return nil }
        return id.uuidString
    }
}

enum DownloadedAppBundleReplacement {
    static func install(source: URL, target: URL, beforeReplacing: () throws -> Void = {},
                        validate: (URL) throws -> Void) throws {
        let manager = FileManager.default
        try validate(source)
        let parent = target.deletingLastPathComponent()
        let suffix = UUID().uuidString
        let staged = parent.appendingPathComponent(".Squat-for-Mac-install-\(suffix).app", isDirectory: true)
        let backupName = ".Squat-for-Mac-backup-\(suffix).app"
        let backup = parent.appendingPathComponent(backupName, isDirectory: true)
        var completed = false
        defer {
            try? manager.removeItem(at: staged)
            if completed { try? manager.removeItem(at: backup) }
        }

        if manager.fileExists(atPath: target.path) {
            let values = try target.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else { throw DownloadedAppInstallError.invalidTarget }
        }
        try manager.copyItem(at: source, to: staged)
        try validate(staged)

        if manager.fileExists(atPath: target.path) {
            try beforeReplacing()
            do {
                _ = try manager.replaceItemAt(target, withItemAt: staged, backupItemName: backupName,
                                              options: [.usingNewMetadataOnly, .withoutDeletingBackupItem])
                try validate(target)
            } catch {
                if manager.fileExists(atPath: backup.path) {
                    try? manager.removeItem(at: target)
                    do { try manager.moveItem(at: backup, to: target) }
                    catch { throw DownloadedAppInstallError.rollbackFailed(backup) }
                }
                throw error
            }
        } else {
            do {
                try manager.moveItem(at: staged, to: target)
                try validate(target)
            } catch {
                try? manager.removeItem(at: target)
                throw error
            }
        }
        completed = true
    }
}

enum DownloadedAppInstallError: LocalizedError {
    case invalidApplication
    case invalidSignature
    case invalidTarget
    case oldVersionIsRunning
    case rollbackFailed(URL)

    var errorDescription: String? {
        switch self {
        case .invalidApplication: return "ダウンロードしたアプリの内容を確認できません。"
        case .invalidSignature: return "アプリの署名を確認できません。"
        case .invalidTarget: return "アプリケーションフォルダの置き換え先が通常のアプリではありません。"
        case .oldVersionIsRunning: return "旧版を終了できませんでした。メニューバーから終了して、もう一度お試しください。"
        case .rollbackFailed(let backup): return "旧版を自動で戻せませんでした。旧版は \(backup.path) に残っています。"
        }
    }
}

@MainActor enum DownloadedAppInstaller {
    private static let bundleIdentifier = "local.thinkandmove.mvp"
    private static let appName = "Squat for Mac.app"

    /// Offers a local install only for a newer downloaded production build.
    /// Returns true after installation starts relaunching the Applications copy.
    static func offerIfNeeded() -> Bool {
        guard Bundle.main.bundleIdentifier == bundleIdentifier,
              let sourceVersion = bundleInfo(at: Bundle.main.bundleURL)?["CFBundleShortVersionString"] as? String,
              let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first else { return false }
        let source = Bundle.main.bundleURL.standardizedFileURL
        let target = applications.appendingPathComponent(appName, isDirectory: true).standardizedFileURL
        let targetExists = FileManager.default.fileExists(atPath: target.path)
        let installedInfo = targetExists ? bundleInfo(at: target) : nil
        let installedVersion = installedInfo?["CFBundleShortVersionString"] as? String
        let inheritedStorageProfile = DownloadedAppStorageMigration.profile(fromBundleInfo: installedInfo)
        let action = DownloadedAppInstallPolicy.action(sourceURL: source, targetURL: target, sourceVersion: sourceVersion,
                                                       installedVersion: installedVersion, targetExists: targetExists)
        guard action != .none else { return false }

        let alert = NSAlert()
        alert.alertStyle = .informational
        if action == .replace {
            alert.messageText = "Squat for Macを更新しますか？"
            alert.informativeText = "アプリケーションフォルダの旧版をバージョン\(sourceVersion)へ置き換えます。運動記録と設定は削除しません。"
            alert.addButton(withTitle: "置き換える")
        } else {
            alert.messageText = "Squat for Macをインストールしますか？"
            alert.informativeText = "バージョン\(sourceVersion)をアプリケーションフォルダへコピーします。"
            alert.addButton(withTitle: "インストール")
        }
        alert.addButton(withTitle: "このまま使う")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }

        do {
            try validateBundle(at: source, expectedVersion: sourceVersion)
            try DownloadedAppBundleReplacement.install(source: source, target: target, beforeReplacing: stopInstalledCopy) {
                try validateBundle(at: $0, expectedVersion: sourceVersion)
            }
            if let inheritedStorageProfile {
                // Older personal builds kept this opaque profile ID in their bundle.
                // Preserve it outside the signed app so future generic releases keep
                // using the same preferences and database without modifying the bundle.
                UserDefaults.standard.set(inheritedStorageProfile, forKey: DownloadedAppStorageMigration.profileKey)
            }
        } catch {
            let failure = NSAlert()
            failure.alertStyle = .warning
            failure.messageText = action == .replace ? "置き換えられませんでした" : "インストールできませんでした"
            failure.informativeText = "旧版と記録は変更していません。Finderでアプリケーションフォルダへ移動してください。\n\n\(error.localizedDescription)"
            failure.runModal()
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
            MainActor.assumeIsolated {
                if let error {
                    let failure = NSAlert()
                    failure.alertStyle = .warning
                    failure.messageText = "更新したアプリを開けませんでした"
                    failure.informativeText = "アプリケーションフォルダからSquat for Macを開いてください。\n\n\(error.localizedDescription)"
                    failure.runModal()
                }
                NSApp.terminate(nil)
            }
        }
        return true
    }

    private static func stopInstalledCopy() throws {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
        others.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(8)
        while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        if others.contains(where: { !$0.isTerminated }) { throw DownloadedAppInstallError.oldVersionIsRunning }
    }

    static func validateBundle(at url: URL, expectedVersion: String) throws {
        let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard values.isSymbolicLink != true, values.isDirectory == true,
              let info = bundleInfo(at: url),
              info["CFBundleIdentifier"] as? String == bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == expectedVersion else { throw DownloadedAppInstallError.invalidApplication }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate), nil) == errSecSuccess else {
            throw DownloadedAppInstallError.invalidSignature
        }
    }

    private static func bundleInfo(at url: URL) -> [String: Any]? {
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return object as? [String: Any]
    }

}
