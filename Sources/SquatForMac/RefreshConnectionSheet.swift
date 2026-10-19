import SwiftUI
import AppKit

struct RefreshConnectionSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var discovery = RefreshPluginDiscovery()
    @State private var help = false
    private var canUseAfterSend: Bool {
        usage.connection == "verified" && settings.pluginLinkEnabled &&
        discovery.installation.state != .notInstalled && discovery.installation.state != .disabled
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(settings.t("通知タイミング", "Reminder timing")).font(.system(size: 23, weight: .medium))
                Button { settings.reminderTriggerMode = .time } label: {
                    Label(settings.t("設定時間になったら", "At the set interval"), systemImage: settings.reminderTriggerMode == .time ? "largecircle.fill.circle" : "circle")
                }.buttonStyle(.plain).frame(minHeight: 36)
                Button {
                    if canUseAfterSend { settings.reminderTriggerMode = .afterSend }
                    else { help = true }
                } label: {
                    Label(settings.t("AIに指示を送ったあと", "After sending a message"), systemImage: settings.reminderTriggerMode == .afterSend ? "largecircle.fill.circle" : "circle")
                }.buttonStyle(.plain).frame(minHeight: 36)
                Text(settings.t("送信連携の検証対象：Codexのローカル環境。通常のChatGPT・Claudeには対応していません。", "Send integration is being tested with local Codex. Regular ChatGPT and Claude are not supported."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text("Squat Link · Codex").font(.system(size: 16, weight: .medium))
                HStack(alignment: .top) {
                    Text(settings.t("導入状態", "Installation")); Spacer()
                    Text(discovery.checking ? settings.t("確認中…", "Checking…") : installationText)
                }
                if let version = discovery.installation.version {
                    Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) { Text(settings.t("接続状態", "Connection")); Spacer(); Text(connectionText) }
                if let date = usage.lastReceived {
                    Text(settings.t("最終受信：", "Last received: ") + date.formatted(date: .omitted, time: .standard)).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack {
                    Button(settings.t("導入状態を再確認", "Refresh status")) { Task { await discovery.refresh() } }.disabled(discovery.checking)
                    Button(settings.t("導入ガイド", "Setup guide")) { help = true }
                }
                HStack {
                    Button(settings.t("接続テストを始める", "Start connection test")) { usage.beginConnectionTest() }
                    Button(settings.t("連携を無効化", "Disable connection")) { usage.disableConnection() }
                }
                Text(settings.t("導入しただけでは接続済みになりません。許可後のテスト送信を受信して確認します。", "Installation alone doesn't confirm a connection. Trust the hook, then send a test message."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text(settings.t("運動していない場合、次の通知タイミングか45分後の早い方でもう一度お知らせします。", "If you haven't exercised, we'll remind you at the next reminder time or after 45 minutes, whichever comes first."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if settings.reminderTriggerMode == .afterSend {
                    Text(settings.t("45分後の再通知は、送信を待たずに表示します。", "The 45-minute follow-up does not wait for another message.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }.font(.system(size: 14)).padding(20)
        }.frame(width: 402, height: 570).background(Color.white).foregroundStyle(.black)
            .task {
                if Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-fixture=") }), CommandLine.arguments.contains("--review-sheet=help") { help = true }
                await discovery.refresh()
            }
            .sheet(isPresented: $help) { RefreshPluginHelp(settings: settings, usage: usage, discovery: discovery) }
    }
    private var installationText: String {
        switch discovery.installation.state {
        case .notInstalled: return settings.t("未導入", "Not installed")
        case .disabled: return settings.t("導入済み・無効", "Installed · disabled")
        case .installed: return settings.t("導入済み・有効", "Installed · enabled")
        case .unknown: return settings.t("状態を確認できません", "Could not check status")
        }
    }
    private var connectionText: String {
        if !settings.pluginLinkEnabled { return settings.t("連携オフ", "Off") }
        switch usage.connection {
        case "verified": return canUseAfterSend ? settings.t("接続済み", "Connected") : settings.t("受信済み・導入状態を確認", "Received · check installation")
        case "verifying": return settings.t("テスト送信を待っています", "Waiting for a test message")
        case "unavailable": return settings.t("受信を開始できません", "Could not start receiver")
        default: return settings.t("受信未確認", "Not verified")
        }
    }
}

struct RefreshPluginHelp: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    @ObservedObject var discovery: RefreshPluginDiscovery
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    private var package: URL? { Bundle.main.resourceURL?.appendingPathComponent("SquatPlugin/marketplace", isDirectory: true) }
    private var commands: String? {
        guard let package, FileManager.default.fileExists(atPath: package.appendingPathComponent(".agents/plugins/marketplace.json").path) else { return nil }
        let executable = RefreshPluginInventory.executable()?.path ?? "codex"
        return "\(quote(executable)) plugin marketplace add \(quote(package.path))\n\(quote(executable)) plugin add \(RefreshPluginInstallation.pluginID)"
    }
    private func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(settings.t("Squat Linkの導入", "Set up Squat Link")).font(.system(size: 22, weight: .medium))
                Text(settings.t("Codexのローカル環境向けの確認版です。回答完了の検知や通常ChatGPT・Claudeの送信連携は含みません。", "A review integration for local Codex. It doesn't detect response completion or messages in regular ChatGPT or Claude."))
                step("1", settings.t("プラグインを導入", "Install the plugin"), settings.t("同梱パッケージを確認し、下のコマンドをターミナルで実行します。Squatは自動で導入しません。", "Inspect the bundled package, then run the commands below in Terminal. Squat doesn't install it automatically."))
                HStack {
                    Button(copied ? settings.t("コピーしました", "Copied") : settings.t("導入コマンドをコピー", "Copy install commands")) {
                        guard let commands else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(commands, forType: .string); copied = true
                    }.disabled(commands == nil)
                    Button(settings.t("同梱パッケージを見る", "View package")) { if let package { NSWorkspace.shared.open(package) } }.disabled(commands == nil)
                }
                if commands == nil { Text(settings.t("同梱パッケージが見つかりません。確認版アプリを再配置してください。", "The bundled package is missing. Restore the review app package.")).foregroundStyle(.red) }
                if let commands { Text(commands).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                step("2", settings.t("有効化・許可", "Enable and trust"), settings.t("ChatGPTデスクトップアプリのプラグイン管理でSquat Linkを有効化します。Codex側のフック確認で処理内容を確認して許可し、案内に従って新しいチャットを開いてください。導入とフックの許可は別です。", "Enable Squat Link in the desktop app's plugin manager. Review and trust its hook in Codex, then start a new chat as instructed. Installing and trusting the hook are separate steps."))
                Button(settings.t("導入状態を再確認", "Refresh installation status")) { Task { await discovery.refresh() } }.disabled(discovery.checking)
                step("3", settings.t("テスト送信", "Send a test message"), settings.t("接続テストを始めてから、実在する作業フォルダのCodexチャットで短い指示を送信してください。受信すると接続済みになります。通知タイミングはその後、ご自身で切り替えます。", "Start the connection test, then send a short message in a local Codex chat with an existing working folder. A received event confirms the connection. Select the reminder timing yourself afterward."))
                Button(settings.t("接続テストを始める", "Start connection test")) { usage.beginConnectionTest() }
                Text(testText).font(.system(size: 12)).foregroundStyle(.secondary)
                Divider()
                Text(settings.t("届かないとき", "If no event arrives")).fontWeight(.medium)
                Text(settings.t("導入状態を再確認し、有効化・フックの許可・新しいCodexチャットを確認してください。削除された作業フォルダのチャットや通常Chatでは試せません。接続テストは約2分で期限切れになるため、もう一度開始してください。", "Refresh the installation status. Check that the plugin is enabled, the hook is trusted, and you're using a new local Codex chat with an existing working folder. Regular Chat is unsupported. Restart the test if its two-minute window expires."))
                Text(settings.t("扱う情報と解除", "Data and removal")).fontWeight(.medium)
                Text(settings.t("ホストからフックへ入力が渡りますが、同梱処理は会話本文を保存・転送せず、送信イベントの識別情報だけをMac内のSquatへ渡します。外部AIは呼び出しません。解除するときはSquatで連携を無効化し、ホストのプラグイン管理からSquat Linkを削除してください。", "The host passes hook input to the helper. The helper doesn't save or forward conversation text; it sends event identifiers to Squat on this Mac without calling an AI service. To remove it, disable the connection in Squat and uninstall Squat Link in the host's plugin manager."))
                Link(settings.t("OpenAI公式のフック説明", "Official OpenAI hook documentation"), destination: URL(string: "https://learn.chatgpt.com/docs/hooks")!)
                HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            }.font(.system(size: 13)).padding(24)
        }.frame(width: 402, height: 590).background(Color.white).foregroundStyle(.black)
    }
    private var testText: String {
        switch usage.connection {
        case "verified": return settings.t("テスト送信を受信しました。", "Test message received.")
        case "verifying": return settings.t("Codexからのテスト送信を待っています。", "Waiting for a test message from Codex.")
        case "unavailable": return settings.t("受信を開始できませんでした。アプリを開き直して再試行してください。", "Could not start the receiver. Reopen Squat and try again.")
        default: return settings.t("接続テストはまだ開始していません。", "The connection test hasn't started.")
        }
    }
    private func step(_ number: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(number). \(title)").font(.system(size: 16, weight: .medium))
            Text(body).fixedSize(horizontal: false, vertical: true)
        }
    }
}
