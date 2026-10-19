import Foundation
import CryptoKit
import Darwin

// No output, model requests, retries, or host control messages.
// This executable is launched by the host's async command handler.
let began = ProcessInfo.processInfo.systemUptime
DispatchQueue.global().asyncAfter(deadline: .now()+0.1) { _exit(0) }
func run() {
    let preview = CommandLine.arguments.contains("--preview")
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(preview ? "SquatPreviewV27/Link" : "Squat/Link",isDirectory: true)
    guard let gateData = try? Data(contentsOf: base.appendingPathComponent("gate.json")), gateData.count <= 1024,
          let gate = try? JSONSerialization.jsonObject(with: gateData) as? [String: Any],
          let generation = gate["generation"] as? String, UUID(uuidString: generation) != nil,
          let expiry = gate["expiresAt"] as? Double, expiry > began, expiry < began + 4,
          let armed = gate["armedAt"] as? Double, let test = gate["testUntil"] as? Double,
          armed >= 0 || test > began else { return }
    let input = FileHandle.standardInput.readData(ofLength: 1_048_577)
    guard input.count <= 1_048_576,
          let object = try? JSONSerialization.jsonObject(with: input) as? [String: Any],
          object["hook_event_name"] as? String == "UserPromptSubmit",
          let session = object["session_id"] as? String, !session.isEmpty, session.utf8.count <= 256,
          let turn = object["turn_id"] as? String, !turn.isEmpty, turn.utf8.count <= 256,
          let token = try? String(contentsOf: base.appendingPathComponent("token"),encoding: .utf8), token.count == 64 else { return }
    func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x",$0) }.joined() }
    let output: [String: Any] = ["protocolVersion": 1,"eventType": "user_prompt_submit","source": "codex-local",
        "callID": UUID().uuidString.lowercased(),"eventID": hash(session+"|"+turn),"sessionTag": hash(session),
        "token": token,"generation": generation,"startedAt": began]
    guard var bytes = try? JSONSerialization.data(withJSONObject: output), bytes.count < 2048 else { return }; bytes.append(10)
    let path = base.appendingPathComponent("events.sock").path
    guard path.utf8.count < 104 else { return }
    let fd = socket(AF_UNIX,SOCK_STREAM,0); guard fd >= 0 else { return }; defer { close(fd) }
    _ = fcntl(fd,F_SETFL,O_NONBLOCK)
    var noSignal: Int32 = 1
    _ = withUnsafePointer(to: &noSignal) { setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,$0,socklen_t(MemoryLayout<Int32>.size)) }
    var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX); address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(path.utf8)+[0]) }
    let connected = withUnsafePointer(to: &address) { p in p.withMemoryRebound(to: sockaddr.self,capacity: 1) { connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size)) } }
    guard connected == 0 else { return }
    var uid: uid_t = 0, gid: gid_t = 0
    guard getpeereid(fd,&uid,&gid) == 0, uid == getuid() else { return }
    _ = bytes.withUnsafeBytes { Darwin.send(fd,$0.baseAddress,$0.count,0) }
}
run()
