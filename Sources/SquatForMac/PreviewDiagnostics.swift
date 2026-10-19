import Foundation

/// Development-only observations of Squat's own UI. No frames or external app data.
@MainActor enum PreviewDiagnostics {
    static func record(_ event: String, values: [String: Any] = [:]) {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27" else { return }
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("preview-ui-events.jsonl")
        var payload = values
        payload["event"] = event
        payload["uptime"] = ProcessInfo.processInfo.systemUptime
        payload["version"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        defer { try? file.close() }
        do { try file.seekToEnd(); try file.write(contentsOf: data) } catch { }
    }
}
