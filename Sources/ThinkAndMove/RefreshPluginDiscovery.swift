import Foundation
import Combine
import Darwin

struct RefreshPluginInstallation: Equatable {
    enum State: String { case unknown, notInstalled, disabled, installed }
    static let pluginID = "squat-link-review@squat-review-v27"
    var state: State = .unknown
    var version: String?

    static func parse(_ data: Data, exitCode: Int32) -> Self {
        guard exitCode == 0, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = object["installed"] as? [[String: Any]] else { return .init() }
        let matches = installed.filter { ($0["pluginId"] as? String) == pluginID }
        guard !matches.isEmpty else { return .init(state: .notInstalled) }
        guard matches.count == 1, let entry = matches.first,
              let present = entry["installed"] as? Bool, let enabled = entry["enabled"] as? Bool else { return .init() }
        return .init(state: !present ? .notInstalled : enabled ? .installed : .disabled, version: entry["version"] as? String)
    }
}

/// Runs only the host's read-only inventory command, never install/enable/trust.
enum RefreshPluginInventory {
    static func executable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            home + "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex"
        ]
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
    static func read() -> RefreshPluginInstallation {
        guard let executable = executable() else { return .init() }
        return read(executable: executable, arguments: ["plugin", "list", "--marketplace", "squat-review-v27", "--json"])
    }
    static func read(executable: URL, arguments: [String], timeout: TimeInterval = 4) -> RefreshPluginInstallation {
        let process = Process(), output = Pipe(), collector = InventoryOutput()
        process.executableURL = executable; process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return .init() }
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global(qos: .utility).async {
            defer { group.leave() }
            while let chunk = try? output.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty { collector.append(chunk) }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline { Thread.sleep(forTimeInterval: 0.02) }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let grace = ProcessInfo.processInfo.systemUptime + 0.2
            while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        guard group.wait(timeout: .now() + 0.5) == .success, !timedOut,
              let data = collector.result else { return .init() }
        return RefreshPluginInstallation.parse(data, exitCode: process.terminationStatus)
    }
}

private final class InventoryOutput {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        guard !overflow else { return }
        guard data.count + chunk.count <= 262_144 else { overflow = true; data.removeAll(); return }
        data.append(chunk)
    }
    var result: Data? { lock.lock(); defer { lock.unlock() }; return overflow ? nil : data }
}

@MainActor final class RefreshPluginDiscovery: ObservableObject {
    @Published private(set) var installation = RefreshPluginInstallation()
    @Published private(set) var checking = false
    @Published private(set) var checkedAt: Date?
    func refresh() async {
        guard !checking else { return }
        checking = true
        installation = await Task.detached(priority: .utility) { RefreshPluginInventory.read() }.value
        checkedAt = Date(); checking = false
    }
}
