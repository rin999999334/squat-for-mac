import Foundation
import Darwin
import Security

/// The sole listener lives inside Squat. It accepts one bounded, authenticated local event.
@MainActor final class SquatLocalLink {
    let directory: URL
    private var descriptor: Int32 = -1
    private var nonce = ""
    private var testUntil: Double = 0
    private var epoch = UUID()
    init(preview: Bool) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent(preview ? "SquatPreviewV27/Link" : "Squat/Link", isDirectory: true)
    }
    func start(receive: @escaping (RefreshSendSignal) -> Void) throws {
        if descriptor >= 0 { testUntil = ProcessInfo.processInfo.systemUptime + 120; return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var ready = false
        defer {
            if !ready {
                for name in ["token", "gate.json", "events.sock"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            }
        }
        var random = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, random.count, &random) == errSecSuccess else { throw LinkError.setup }
        nonce = random.map { String(format: "%02x", $0) }.joined()
        let tokenURL = directory.appendingPathComponent("token")
        try Data(nonce.utf8).write(to: tokenURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
        let path = directory.appendingPathComponent("events.sock").path
        guard path.utf8.count < 104 else { throw LinkError.setup }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw LinkError.setup }
        var a = sockaddr_un(); a.sun_family = sa_family_t(AF_UNIX); a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let raw = Array(path.utf8) + [0]
        withUnsafeMutableBytes(of: &a.sun_path) { $0.copyBytes(from: raw) }
        let result = withUnsafePointer(to: &a) { p in p.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else { close(fd); throw LinkError.setup }
        let listener = dup(fd)
        guard listener >= 0 else { close(fd); throw LinkError.setup }
        descriptor = fd; testUntil = ProcessInfo.processInfo.systemUptime + 120; epoch = UUID(); ready = true
        setGate(generation: UUID().uuidString.lowercased(), armedAt: nil)
        let expected = nonce
        let expectedEpoch = epoch
        DispatchQueue.global(qos: .utility).async {
            defer { close(listener) }
            while true {
                let c = accept(listener, nil, nil)
                if c < 0 { break }
                defer { close(c) }
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(c, &uid, &gid) == 0, uid == getuid() else { continue }
                var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
                _ = withUnsafePointer(to: &timeout) { setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size)) }
                var bytes = [UInt8](repeating: 0, count: 2049), data = Data()
                while data.count < 2049 {
                    let n = recv(c, &bytes, 2049 - data.count, 0)
                    if n <= 0 { break }
                    data.append(contentsOf: bytes.prefix(n)); if data.contains(10) { break }
                }
                guard data.count <= 2048,
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      Set(object.keys) == Set(["protocolVersion", "eventType", "source", "callID", "eventID", "sessionTag", "token", "generation", "startedAt"]),
                      let signal = try? JSONDecoder().decode(RefreshSendSignal.self, from: data),
                      signal.protocolVersion == 1, signal.eventType == "user_prompt_submit", signal.source == "codex-local",
                      signal.token == expected, UUID(uuidString: signal.callID) != nil, UUID(uuidString: signal.generation) != nil,
                      signal.startedAt.isFinite,
                      signal.eventID.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
                      signal.sessionTag.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { continue }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.descriptor >= 0, self.epoch == expectedEpoch else { return }
                    receive(signal)
                }
            }
        }
    }
    func setGate(generation: String, armedAt: Double?) {
        guard descriptor >= 0 else { return }
        let object: [String: Any] = ["generation": generation, "armedAt": armedAt ?? -1,
                                     "testUntil": testUntil, "expiresAt": ProcessInfo.processInfo.systemUptime + 3]
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        let url = directory.appendingPathComponent("gate.json")
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func stop() {
        epoch = UUID()
        guard descriptor >= 0 else { return }
        let fd = descriptor; descriptor = -1
        shutdown(fd, SHUT_RDWR); close(fd)
        for name in ["events.sock", "token", "gate.json"] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
    }
    enum LinkError: Error { case setup }
}
