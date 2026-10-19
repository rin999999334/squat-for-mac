import SwiftUI

struct SquatRootView: View {
    @ObservedObject var coordinator: AppCoordinator
    let store: MoveStore
    let history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    let selection: ProgressSelection
    let usageMonitor: ForegroundUsageMonitor
    var testInvitation: (Bool) -> Void
    var titlebarHeight: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTutorial = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.white.ignoresSafeArea()
                switch coordinator.screen {
                case .welcome:
                    SquatWelcomeView(settings: settings, tryIt: { showTutorial = true }, skip: { coordinator.completeOnboarding() })
                case .home, .history:
                    SquatHomeView(coordinator: coordinator, store: store, history: history, settings: settings, selection: selection, designOffset: 22 - titlebarHeight)
                case .settings:
                    SquatSettingsView(coordinator: coordinator, settings: settings, usageMonitor: usageMonitor, testInvitation: testInvitation)
                case .prepare, .workout:
                    SquatWorkoutView(coordinator: coordinator, store: store, settings: settings)
                case .result:
                    SquatResultView(coordinator: coordinator, history: history, settings: settings)
                }
            }.foregroundStyle(SquatDesign.ink).preferredColorScheme(.light)
                .animation(reduceMotion ? nil : SquatMotion.page, value: transitionGroup)
                .sheet(isPresented: $showTutorial) { tutorial(size: geometry.size) }
                .onExitCommand { if store.active { coordinator.finish() } else if coordinator.screen != .welcome { coordinator.goHome() } }
        }
    }
    private var transitionGroup: Int {
        switch coordinator.screen { case .welcome: return 0; case .home, .history: return 1; case .settings: return 2; case .prepare, .workout: return 3; case .result: return 4 }
    }
    private func tutorial(size: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SquatLogo(width: 100)
                Text(settings.t("まずは、5回だけ。", "Start with just five.")).font(SquatDesign.text(23, japanese: settings.isJapanese))
                instruction("1", settings.t("立ち上がって、顔をカメラに映します。", "Stand up and keep your face in the camera."))
                instruction("2", settings.t("まっすぐ立ち、3秒待ちます。", "Stand still for three seconds."))
                instruction("3", settings.t("ゆっくり下がって、元の高さへ戻ります。", "Lower yourself, then return to your starting height."))
                Text(settings.t("顔の上下の動きを数えます。映像は保存・送信しません。", "Squat counts vertical face movement. Video is never saved or sent."))
                    .font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(settings.t("戻る", "Back")) { showTutorial = false }.buttonStyle(.plain)
                    Spacer()
                    Button(settings.t("カメラで5回試す", "Try 5 with camera")) { showTutorial = false; coordinator.start(tutorial: true) }.buttonStyle(SquatPrimaryButton())
                }
            }.padding(25)
        }.frame(width: max(300, min(400, size.width)), height: max(300, min(500, size.height))).background(.white)
    }
    private func instruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(SquatDesign.number(14)).foregroundStyle(SquatDesign.blue).frame(width: 25, height: 25)
            Text(text).font(SquatDesign.ui(15)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SquatHeader: View {
    var settings: (() -> Void)? = nil
    var back: (() -> Void)? = nil
    var japanese = false
    var body: some View {
        ZStack {
            SquatLogo()
            HStack {
                if let back { Button(action: back) { Image(systemName: "chevron.left").frame(width: 32, height: 32) }.accessibilityLabel(japanese ? "戻る" : "Back") }
                Spacer()
                if let settings { Button(action: settings) { Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 32, height: 32) }.accessibilityLabel(japanese ? "設定" : "Settings") }
            }.buttonStyle(.plain).foregroundStyle(SquatDesign.muted)
        }.frame(height: 42).padding(.horizontal, 10).padding(.top, 6)
    }
}

private struct SquatHomeView: View {
    let coordinator: AppCoordinator
    @ObservedObject var store: MoveStore
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    let selection: ProgressSelection
    let designOffset: CGFloat
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                ZStack(alignment: .top) {
                    LinearGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.28),
                                           .init(color: SquatDesign.blue.opacity(0.64), location: 0.67),
                                           .init(color: SquatDesign.blue, location: 1)], startPoint: .top, endPoint: .bottom)
                    SquatHeader(settings: { coordinator.openSettings() }, japanese: settings.isJapanese).offset(y: designOffset)
                    GoalRing(goal: $store.goal, japanese: settings.isJapanese, hapticsEnabled: settings.hapticsEnabled, start: { coordinator.start() })
                        .disabled(!history.canRecord).padding(.top, 67 + designOffset)
                    SquatWeekCompletion(history: history).padding(.horizontal, 10).padding(.top, 352 + designOffset)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.t("記録", "Record")).font(SquatDesign.text(11, japanese: settings.isJapanese)).foregroundStyle(.white)
                        SquatProgressView(history: history, settings: settings, selection: selection)
                    }.padding(.horizontal, 20).padding(.top, 424 + designOffset)
                }.frame(maxWidth: 500).frame(height: max(684 + designOffset, geometry.size.height), alignment: .top)
                    .frame(maxWidth: .infinity)
                if history.saveState == .failed { StorageFailureView(coordinator: coordinator, settings: settings).padding(20) }
                else if let message = history.recoveryMessage { Text(message).font(SquatDesign.ui(11)).foregroundStyle(SquatDesign.muted).padding(20) }
            }.scrollIndicators(.hidden)
                .onChange(of: store.goal) { _ in store.saveSettings() }
        }
    }
}

private struct SquatWeekCompletion: View {
    @ObservedObject var history: WorkoutHistory
    var body: some View {
        let calendar = ProgressCalendarModel.localCalendar(timeZone: history.calendarTimeZone)
        let bounds = ProgressCalendarModel.bounds(period: .week, anchor: history.currentDate, calendar: calendar)
        let counts = Dictionary(uniqueKeysWithValues: history.dayCounts(from: bounds.0, through: bounds.1).map { ($0.date, $0.count) })
        let model = ProgressCalendarModel(period: .week, anchor: history.currentDate, counts: counts, today: history.currentDate, calendar: calendar)
        HStack(spacing: 5) {
            ForEach(Array(model.days.enumerated()), id: \.element.date) { index, day in
                VStack(spacing: 6) {
                    Text(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][index]).font(SquatDesign.text(14)).foregroundStyle(.white)
                    Circle().fill(day.count > 0 && !day.future ? SquatDesign.blue : .white.opacity(day.future ? 0.6 : 1))
                        .overlay { if day.count > 0 && !day.future { Image(systemName: "checkmark").font(.system(size: 12)).foregroundStyle(.white) } }
                        .frame(width: 25, height: 25)
                }.frame(maxWidth: .infinity)
                    .help("\(calendar.component(.month, from: day.date))/\(calendar.component(.day, from: day.date)) · \(day.count)")
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.date.formatted(date: .complete, time: .omitted)), \(day.count)")
            }
        }
    }
}

private struct SquatWelcomeView: View {
    @ObservedObject var settings: AppSettings
    let tryIt: () -> Void
    let skip: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Text(settings.t("ようこそ", "Welcome to")).font(SquatDesign.ui(20)).foregroundStyle(SquatDesign.muted).padding(.bottom, 8)
                    Text("Squat").font(SquatDesign.text(64)).foregroundStyle(SquatDesign.blue)
                    Text(settings.t("少ない回数から、\n座りっぱなしを減らしていこう。", "Squat helps you sit less and move more\nstarting with just one or two squats."))
                        .font(SquatDesign.text(16, japanese: settings.isJapanese)).foregroundStyle(SquatDesign.muted).multilineTextAlignment(.center)
                        .lineSpacing(7).fixedSize(horizontal: false, vertical: true).padding(.top, 38)
                    Button(settings.t("5回試す", "Go tutorial"), action: tryIt).buttonStyle(SquatPrimaryButton()).keyboardShortcut(.defaultAction).padding(.top, 42)
                    Button(settings.t("スキップ", "Skip"), action: skip).font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted).buttonStyle(.plain).padding(8)
                }.padding(.horizontal, 25).padding(.vertical, 30)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .opacity(revealed ? 1 : 0).offset(y: revealed || reduceMotion ? 0 : 6)
            }
        }.onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) { revealed = true } }
    }
}

private struct SquatSettingsView: View {
    let coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    @ObservedObject var usageMonitor: ForegroundUsageMonitor
    let testInvitation: (Bool) -> Void
    @State private var information: String?
    private var preview: Bool { Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27" }
    var body: some View {
        VStack(spacing: 16) {
            SquatHeader(back: { coordinator.goHome() }, japanese: settings.isJapanese)
            Text(settings.t("設定", "Settings")).font(SquatDesign.text(14, japanese: settings.isJapanese)).foregroundStyle(SquatDesign.muted)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Toggle(settings.t("休憩を提案する", "Suggest a short break"), isOn: $settings.usageRemindersEnabled)
                        .toggleStyle(.switch).tint(SquatDesign.blue)
                    Text(settings.t("対象アプリを累計\(settings.usageReminderInterval.rawValue)分使ったら、運動に誘います。会話の内容は読み取りません。", "Get a suggestion after \(settings.usageReminderInterval.rawValue) minutes in your selected app. Conversation content is never read."))
                        .font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted).fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.t("案内までの利用時間", "Usage before a suggestion")).font(SquatDesign.ui(12))
                        SquatSegmentedControl(options: UsageReminderInterval.allCases, selected: settings.usageReminderInterval,
                            title: { settings.t("\($0.rawValue)分", "\($0.rawValue) min") }, identifier: { "usage-interval-\($0.rawValue)" },
                            select: { settings.usageReminderInterval = $0 }, usesInterfaceFont: true)
                            .frame(height: 30)
                    }
                    SquatSegmentedControl(options: AIProvider.allCases, selected: settings.aiProvider,
                        title: { $0 == .chatgptDesktop ? "ChatGPT / Codex" : "Claude" }, identifier: { "provider-\($0.rawValue)" }, select: { settings.aiProvider = $0 }, usesInterfaceFont: true)
                        .frame(height: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settings.t("累計 \(usageMonitor.progress.elapsedMinutes) / \(usageMonitor.progress.targetMinutes) 分", "Usage: \(usageMonitor.progress.elapsedMinutes) / \(usageMonitor.progress.targetMinutes) min"))
                            .font(SquatDesign.number(15)).accessibilityIdentifier("usage-progress")
                        Text(usageMonitor.statusText(japanese: settings.isJapanese)).font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(settings.t("Squatを起動しているだけでは増えません。ブラウザ版は対象外です。", "Keeping Squat open does not count. Browser chats are not included."))
                            .font(SquatDesign.ui(11)).foregroundStyle(SquatDesign.muted).fixedSize(horizontal: false, vertical: true)
                        Button(settings.t("案内を試す", "Test suggestion")) { testInvitation(false) }
                            .buttonStyle(.plain).foregroundStyle(SquatDesign.blue).accessibilityIdentifier("usage-test-suggestion")
                    }
                    if settings.usageRemindersEnabled {
                        Button(settings.t("今日は案内を休止", "Pause suggestions today")) { usageMonitor.pauseToday() }
                            .buttonStyle(.plain).foregroundStyle(SquatDesign.blue)
                    }
                    Divider()
                    informationButton(settings.t("使い方", "How to use"), text: settings.t("ホームの外周リングで回数を調整し、中央を押して開始します。立った姿勢で顔を映して3秒待ち、ゆっくり下がって元の高さへ戻りましょう。", "Drag the ring to set your target, then press the center. Stand upright with your face visible for three seconds. Lower yourself, then return to your starting height."))
                    informationButton(settings.t("プライバシー", "Privacy"), text: settings.t("カメラ映像はこのMacで処理し、保存・送信しません。運動記録と利用時間の集計値はMac内に保存します。会話本文・入力内容・スクリーンショットは取得しません。", "Camera video is processed on this Mac and never saved or sent. Workout records and aggregate usage time stay locally. Conversation text, typed content and screenshots are not collected."))
                    informationButton(settings.t("Squatについて", "About Squat"), text: "Squat \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")\n\nInter / Zalando Sans Expanded · SIL Open Font License")
                    if let information { Text(information).font(SquatDesign.ui(13)).foregroundStyle(SquatDesign.muted).fixedSize(horizontal: false, vertical: true) }
                    if preview {
                        Divider()
                        Button("Preview: invitation") { testInvitation(false) }.buttonStyle(.bordered)
                        Button("Preview: 15s usage test") { testInvitation(true) }.buttonStyle(.bordered)
                        Button("Preview: camera-free demo") { coordinator.start(demo: true) }.buttonStyle(.bordered)
                        Button("Preview: welcome") { coordinator.showWelcomePreview() }.buttonStyle(.bordered)
                    }
                }.padding(.horizontal, 20).padding(.vertical, 16)
            }
        }.font(SquatDesign.ui(13)).background(.white)
    }
    private func informationButton(_ title: String, text: String) -> some View {
        Button { information = information == text ? nil : text } label: {
            HStack { Text(title); Spacer(); Image(systemName: "chevron.right").font(.system(size: 10)) }.contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct SquatResultView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(spacing: 0) {
            SquatHeader()
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: coordinator.result?.completed == true ? "checkmark.circle" : "circle.dashed")
                        .font(.system(size: 42, weight: .ultraLight)).foregroundStyle(SquatDesign.blue).padding(.top, 65)
                    Text(settings.t("おつかれさま。", "A little move. A good moment.")).font(SquatDesign.text(20, japanese: settings.isJapanese))
                    if let result = coordinator.result {
                        Text("\(result.count)").font(SquatDesign.number(72))
                        Text(settings.t("回 / 目標 \(result.target)回", "reps / \(result.target) target")).font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted)
                        if result.isDemo { Text(settings.t("デモの回数は記録に含めません", "Demo repetitions are not recorded")).font(SquatDesign.ui(12)) }
                        else {
                            if history.saveState == .failed { StorageFailureView(coordinator: coordinator, settings: settings) }
                            else if history.saveState == .pending { ProgressView(settings.t("保存中…", "Saving…")) }
                            else { Text(settings.t("このMacに保存済み · 今日 \(history.todayReps)回", "Saved on this Mac · \(history.todayReps) today")).font(SquatDesign.ui(12)).foregroundStyle(SquatDesign.muted) }
                        }
                    }
                    Button(settings.t("ホームへ", "Back home")) { coordinator.goHome() }.buttonStyle(SquatPrimaryButton()).keyboardShortcut(.defaultAction)
                }.multilineTextAlignment(.center).padding(24).frame(maxWidth: .infinity)
            }
        }
    }
}

private struct StorageFailureView: View {
    let coordinator: AppCoordinator
    @ObservedObject var settings: AppSettings
    var body: some View {
        VStack(spacing: 10) {
            Text(settings.t("記録を保存できませんでした。終了前に再試行してください。", "Your record could not be saved. Retry before quitting.")).font(SquatDesign.ui(12))
            Button(settings.t("保存を再試行", "Retry saving")) { coordinator.retrySave() }.buttonStyle(.bordered).tint(SquatDesign.blue)
        }.padding(14).background(.white, in: RoundedRectangle(cornerRadius: 8))
    }
}
