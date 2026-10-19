import SwiftUI

/// Connection verification is an explicit, local setup flow. A selected app or
/// enabled invitation preference alone must never be presented as verified.
struct AIConnectionSettingsView: View {
    @ObservedObject var monitor: AIActivityMonitor
    @ObservedObject var settings: AppSettings
    let testInvitation: () -> Void
    let testUnavailableReason: String?
    @State private var confirmedNormalChat = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(settings.t("AIの待ち時間", "AI wait time")).font(SquatDesign.ui(14, weight: .medium))
            Toggle(settings.t("AIの待ち時間に誘う", "Invite me during AI wait time"), isOn: $settings.aiEnabled)
            Picker(settings.t("対象のアプリ", "Chat app"), selection: $settings.aiProvider) {
                Text("ChatGPT").tag(AIProvider.chatgptDesktop)
                Text("Claude").tag(AIProvider.claudeDesktop)
            }
            note(monitor.status.message(isJapanese: settings.isJapanese))

            note(settings.t("通常のデスクトップチャットが対象です。アプリ名が見つかっても、通常チャットの確認が必要です。Codex・Claude Codeのコード実行画面と、ブラウザのチャットは対象外です。", "Use the regular desktop chat. Finding the app alone does not verify its chat mode. Codex and Claude Code execution screens, and browser chats, are excluded."))
            Toggle(isOn: $confirmedNormalChat) {
                Text(settings.t("通常のチャット画面を開いていることを確認しました", "I have opened the regular chat screen"))
                    .fixedSize(horizontal: false, vertical: true)
            }.toggleStyle(.checkbox)

            Button(settings.t("アクセシビリティを許可", "Allow Accessibility")) { monitor.requestPermission() }
                .buttonStyle(.bordered)
            note(settings.t("許可はMacのシステム設定で変更できます。許可後に、下の3つの状態を確認します。", "You can manage permission in Mac System Settings. Then verify the three states below."))

            if setupInProgress {
                setupProgress
            } else {
                Button(settings.t(monitor.profileVerified ? "接続を確認し直す" : "3ステップで接続を確認", monitor.profileVerified ? "Verify the connection again" : "Verify in 3 steps")) {
                    monitor.beginSetup(provider: settings.aiProvider)
                }.buttonStyle(.bordered).disabled(!confirmedNormalChat)
            }

            if case .connected = monitor.setupStep, monitor.profileVerified {
                Label(settings.t("このアプリのバージョンとチャット画面で確認済み", "Verified for this app version and chat window"), systemImage: "checkmark.circle")
                    .font(SquatDesign.ui(11)).foregroundStyle(SquatDesign.blue)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = monitor.setupErrorMessage(isJapanese: settings.isJapanese) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(SquatDesign.ui(11)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(settings.t("接続確認を完了できませんでした。", "Connection verification could not be completed. ") + error)
            }
            if monitor.profileVerified {
                Button(settings.t("接続の確認をリセット", "Reset connection verification")) {
                    monitor.resetProfile(provider: settings.aiProvider)
                    confirmedNormalChat = false
                }.font(SquatDesign.ui(11)).buttonStyle(.bordered)
            }
            Button(settings.t("接続状態を更新", "Refresh connection status")) { monitor.refreshAvailability() }
                .font(SquatDesign.ui(11)).buttonStyle(.bordered)
            note(settings.t("生成停止ボタンの状態を確認します。会話本文や入力内容は読み取りません。確認できない場合は自動で誘いません。", "Squat checks the generation stop control. It does not read your messages or replies. If the state cannot be verified, no automatic invitation appears."))

            Divider()
            Text(settings.t("案内の表示", "Invitations")).font(SquatDesign.ui(14, weight: .medium))
            Button(settings.t("通知の表示を試す", "Try a test invitation"), action: testInvitation)
                .buttonStyle(.bordered).disabled(testUnavailableReason != nil)
            if let testUnavailableReason { note(testUnavailableReason) }
            note(settings.t("表示確認用のテストです。AIの生成を検知した案内ではありません。", "This is a display test, rather than a detected AI waiting period."))
            Toggle(settings.t("30分ごとの休憩の案内", "A break invitation every 30 minutes"), isOn: $settings.breakRemindersEnabled)
            note(settings.t("AIの待ち時間の検知とは別の、任意の案内です。", "An optional reminder, separate from AI wait detection."))
        }
        .font(SquatDesign.ui(13))
        .onChange(of: settings.aiProvider) { _ in
            monitor.cancelSetup()
            confirmedNormalChat = false
        }
        .onChange(of: confirmedNormalChat) { confirmed in
            if !confirmed && setupInProgress { monitor.cancelSetup() }
        }
        .onDisappear { if setupInProgress { monitor.cancelSetup() } }
    }

    private var setupInProgress: Bool {
        switch monitor.setupStep {
        case .captureIdle, .captureRunning, .captureCompletion: return true
        case .idle, .connected: return false
        }
    }

    private var setupProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(settings.t("手順 \(stepNumber) / 3", "Step \(stepNumber) of 3"))
                .font(SquatDesign.ui(12, weight: .medium)).foregroundStyle(SquatDesign.blue)
            note(stepInstructions)
            note(settings.t("対象のウインドウを最小化せず、Squatに戻って記録してください。", "Keep the chat window open and unminimized, then return to Squat to record it."))
            Button(captureTitle) { monitor.captureSetupStep() }
                .buttonStyle(.borderedProminent).tint(SquatDesign.blue)
                .disabled(!confirmedNormalChat)
            Button(settings.t("接続の確認を中止", "Cancel verification")) { monitor.cancelSetup() }
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
    }

    private var stepNumber: Int {
        switch monitor.setupStep {
        case .captureRunning: return 2
        case .captureCompletion: return 3
        default: return 1
        }
    }
    private var captureTitle: String {
        switch monitor.setupStep {
        case .captureRunning: return settings.t("生成中を記録", "Record generation in progress")
        case .captureCompletion: return settings.t("生成が終わった状態を記録", "Record generation finished")
        default: return settings.t("返答していない状態を記録", "Record the idle state")
        }
    }
    private var stepInstructions: String {
        switch monitor.setupStep {
        case .captureRunning:
            return settings.t("同じチャットで質問を送り、生成停止ボタンが出ている間に記録します。", "Send a message in the same chat. Record it while the generation stop button is visible.")
        case .captureCompletion:
            return settings.t("同じチャットの生成が終わり、生成停止ボタンが消えてから記録します。", "Wait for generation to finish in the same chat, then record it after the stop button disappears.")
        default:
            return settings.t("対象アプリの通常チャットを開き、返答を生成していない状態で記録します。", "Open a regular chat in the selected app. Record it while no reply is being generated.")
        }
    }
    private func note(_ text: String) -> some View {
        Text(text).font(SquatDesign.ui(11)).foregroundStyle(SquatDesign.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
