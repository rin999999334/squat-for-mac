import SwiftUI
import AppKit
import AVFoundation

struct RefreshRootView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var presentation: RefreshPresentation
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    @ObservedObject var history: WorkoutHistory
    let store: MoveStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var message: String?
    @State private var about = false
    @State private var cameraExplanation = false
    @StateObject private var sharing = RefreshShareController()
    @Namespace private var dates
    var body: some View {
        GeometryReader { geometry in
            if presentation.screen == .prepare || presentation.screen == .workout {
                SquatWorkoutView(coordinator: coordinator, store: store, settings: settings).frame(width: 402,height: 706).frame(maxWidth: .infinity,maxHeight: .infinity)
            } else {
                let detail = presentation.screen == .history
                let size = detail ? RefreshGeometry.detail : RefreshGeometry.home
                let extra: CGFloat = presentation.screen == .home && history.saveState == .failed ? 100 : 0
                ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Color.white
                        RefreshChrome(detail: detail, settings: settings,
                                      back: presentation.screen == .settings || detail ? { coordinator.goHome() } : nil,
                                      openSettings: presentation.screen == .settings ? nil : { coordinator.openSettings() }, showShare: presentation.screen != .home && presentation.screen != .welcome, share: share).zIndex(10)
                        // Keep the history view mounted so Settings preserves its year, focus and scroll offset.
                        RefreshHistory(history: history, settings: settings, usage: usage, dates: dates)
                            .frame(width: size.width, height: size.height, alignment: .topLeading).clipped()
                            .opacity(presentation.screen == .history ? 1 : 0)
                            .allowsHitTesting(presentation.screen == .history)
                            .disabled(presentation.screen != .history)
                            .accessibilityHidden(presentation.screen != .history)
                        Group {
                            switch presentation.screen {
                            case .home, .welcome:
                                RefreshHome(coordinator: coordinator, store: store, history: history, settings: settings, usage: usage, dates: dates, start: start, share: share)
                            case .settings:
                                RefreshSettings(settings: settings, usage: usage, showAbout: { about = true }, contact: contact)
                            case .history:
                                EmptyView()
                            case .result:
                                RefreshResult(coordinator: coordinator, history: history, settings: settings)
                            case .prepare, .workout: EmptyView()
                            }
                        }
                        if extra > 0 {
                            VStack(spacing: 10) {
                                Text(settings.t("記録を保存できませんでした。", "Could not save your record."))
                                Button(settings.t("保存を再試行", "Retry saving")) { coordinator.retrySave() }
                            }.font(RefreshDesign.font(14, japanese: settings.isJapanese))
                                .frame(width: 350, height: 70).position(x: 201, y: 750).id("refresh.storageFailure")
                        }
                    }.frame(width: size.width, height: size.height + extra)
                        .opacity(presentation.opacity)
                        .allowsHitTesting(!presentation.isTransitioning)
                        .accessibilityHidden(presentation.isTransitioning)
                        .background(.white).clipShape(RoundedRectangle(cornerRadius: 24))
                        .frame(minWidth: max(size.width, geometry.size.width), minHeight: max(size.height + extra, geometry.size.height), alignment: .center)
                }.scrollIndicators(.hidden)
                    .onChange(of: history.saveState) { _ in if extra > 0 { proxy.scrollTo("refresh.storageFailure", anchor: .bottom) } }
                    .onChange(of: presentation.screen) { _ in if extra > 0 { proxy.scrollTo("refresh.storageFailure", anchor: .bottom) } }
                }
            }
        }.background(Color.white).clipShape(RoundedRectangle(cornerRadius: 24))
            .preferredColorScheme(.light).foregroundStyle(.black)
            .sheet(isPresented: $about) { aboutSheet }
            .sheet(isPresented: Binding(get: { sharing.image != nil || sharing.isPreparing }, set: { if !$0 { sharing.cancel() } })) {
                RefreshShareSheet(settings: settings, sharing: sharing)
            }
            .alert(settings.t("Squatからのお知らせ", "Squat"), isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .task {
                guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27",
                      CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-fixture=") }),
                      let mode = CommandLine.arguments.first(where: { $0.hasPrefix("--review-sheet=") }).map({ String($0.dropFirst(15)) }) else { return }
                try? await Task.sleep(nanoseconds: 300_000_000)
                if mode.hasPrefix("share") {
                    if mode == "share-total" { await sharing.prepare(TotalCardSnapshot.make(history: history, usage: usage)) }
                    else { await sharing.prepare(TodayCardSnapshot.make(history: history, usage: usage)) }
                }
            }
            .onChange(of: sharing.error) { if let error = $0 { message = error; sharing.error = nil } }
            .onExitCommand {
                if store.active { coordinator.finish() }
                else if presentation.screen == .settings { coordinator.closeSettings() }
                else { coordinator.goHome() }
            }
    }
    private func start() {
        refreshStartWithPermission(coordinator: coordinator, settings: settings)
    }
    private func share() {
        guard history.saveState == .recorded else { message = settings.t("記録の保存後にもう一度お試しください。", "Please try again after your record is saved."); return }
        let total = presentation.screen == .history
        let today = TodayCardSnapshot.make(history: history,usage: usage)
        let allTime = TotalCardSnapshot.make(history: history,usage: usage)
        Task {
            if total { await sharing.prepare(allTime) }
            else { await sharing.prepare(today) }
        }
    }
    private func contact() {
        guard let url = settings.contactFormURL else { message = settings.t("お問い合わせ先を準備中です。", "The contact form is being prepared."); return }
        NSWorkspace.shared.open(url)
    }
    private var aboutSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(settings.t("Squatについて", "About Squat")).font(RefreshDesign.font(24, japanese: settings.isJapanese))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
            Text(settings.t("ホームのリングで回数を選び、Go Squatで始めます。", "Set your target using the ring, then press Go Squat."))
            Text(settings.t("映像はMac内で処理します。保存・送信しません。運動記録と利用時間の集計値をMac内に保存します。", "Video is processed on this Mac and never saved or sent. Workout records and aggregate usage time stay on this Mac."))
            Text("Zalando Sans Expanded · SIL Open Font License\nSF Compact Rounded · macOS system font")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { about = false }.keyboardShortcut(.defaultAction) }
        }.font(.system(size: 15)).padding(24).frame(width: 362)
    }
}

private struct RefreshChrome: View {
    let detail: Bool
    @ObservedObject var settings: AppSettings
    var back: (() -> Void)?
    var openSettings: (() -> Void)?
    var showShare = true
    let share: () -> Void
    var body: some View {
        let width: CGFloat = detail ? 802 : 402
        let brandY: CGFloat = detail ? 72 : 48
        ZStack(alignment: .topLeading) {
            RefreshWindowDrag().frame(width: width, height: detail ? 100 : 76)
            Text("Squat").font(.custom(SquatResources.expanded, size: 20)).fontWeight(.regular).tracking(0.4).foregroundStyle(RefreshDesign.blue)
                .fixedSize().position(x: width/2 - 0.5, y: brandY).allowsHitTesting(false)
            if let openSettings {
                Button(action: openSettings) { Image(systemName: "gearshape").resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 26, height: 30) }
                    .buttonStyle(.plain).foregroundStyle(Color(white: 0.7)).position(x: width - 69, y: brandY)
                    .accessibilityLabel(settings.t("設定", "Settings")).accessibilityIdentifier("refresh.settings")
                if showShare { Button(action: share) { Image(systemName: "square.and.arrow.up").resizable().scaledToFit().frame(width: 16, height: 16).frame(width: 26, height: 30) }
                    .buttonStyle(.plain).foregroundStyle(Color(white: 0.7)).position(x: width - 38, y: brandY)
                    .accessibilityLabel(detail ? settings.t("累計の記録をシェア", "Share your total record") : settings.t("今日の記録をシェア", "Share today’s record")) }
            }
            if let back {
                Button(action: back) { HStack(spacing: 3) {
                    Image(systemName: "arrow.left").font(.system(size: 12)).frame(width: 16,height: 16)
                    Text("Home").font(RefreshDesign.font(16)).tracking(0.32).frame(width: 53,height: 19,alignment: .leading)
                }.frame(width: 72,height: 19,alignment: .leading).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(RefreshDesign.secondary).position(x: detail ? 66 : 56, y: detail ? 71.5 : 89.5)
                    .accessibilityLabel(settings.t("Homeへ戻る", "Go Home")).accessibilityIdentifier("refresh.back")
            }
        }.frame(width: width, height: detail ? 115 : 110)
    }
}

private struct RefreshWindowDrag: NSViewRepresentable {
    final class DragView: NSView { override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) } }
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
}

private struct RefreshHome: View {
    let coordinator: AppCoordinator
    @ObservedObject var store: MoveStore
    @ObservedObject var history: WorkoutHistory
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    let dates: Namespace.ID
    let start: () -> Void
    let share: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(history.activeDayCount)").font(RefreshDesign.font(24, medium: true))
                Text("days").font(RefreshDesign.font(16, medium: true))
            }.fixedSize().position(x: 202, y: 109.5)
            RefreshGoalRing(goal: $store.goal, japanese: settings.isJapanese, haptics: settings.hapticsEnabled, commit: store.saveSettings)
            Text("\(store.goal)").font(RefreshDesign.font(96, medium: true)).tracking(1.92).frame(width: 176, height: 115).position(x: 200.5, y: 261.5).allowsHitTesting(false)
            Text("reps").font(RefreshDesign.font(24, medium: true)).tracking(0.48).position(x: 199.5988, y: 341.5).allowsHitTesting(false)
            refreshPill("Go Squat", action: start).position(x: 201, y: 405).disabled(!history.canRecord).accessibilityIdentifier("refresh.start")
            Button { coordinator.openHistory() } label: { HStack(spacing: 3) { Text("Detail").frame(width: 42,alignment: .leading); Image(systemName: "arrow.right").font(.system(size: 12)).frame(width: 16,height: 16) } }
                .font(RefreshDesign.font(16)).tracking(0.32).buttonStyle(.plain).foregroundStyle(RefreshDesign.secondary)
                .frame(width: 63, height: 28,alignment: .leading).position(x: 340.5, y: 676.5).accessibilityIdentifier("refresh.detail")
            TodayCardView(snapshot: TodayCardSnapshot.make(history: history,usage: usage),dates: dates,share: share).position(x: 201,y: 560.5)
        }.frame(width: 402, height: 706)
    }
    private var reference: Bool { CommandLine.arguments.contains("--ui-fixture=refresh-reference") && Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27" }
    private var todayTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "d MMM"
        return "Today・\(f.string(from: history.currentDate))"
    }
    private func statistic(_ title: String, value: String, x: CGFloat, dotX: CGFloat, width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(Color(white: 0.85)).frame(width: 10, height: 10).position(x: dotX + 5, y: 561)
            Text(title).font(RefreshDesign.font(12)).foregroundStyle(RefreshDesign.secondary).frame(width: width, height: 14, alignment: .leading).position(x: x + width/2, y: 561)
            Text(value).font(RefreshDesign.font(20, medium: true)).foregroundStyle(Color(white: 0.98)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(width: width, height: 24, alignment: .leading).position(x: x + width/2, y: 582).help(value)
        }
    }
}

private func refreshPill(_ title: String, action: @escaping () -> Void) -> some View {
    Button(action: action) { Text(title).font(RefreshDesign.font(20, medium: true)).tracking(0.4).foregroundStyle(.white).frame(width: 130, height: 30).background(RefreshDesign.blue, in: Capsule()) }
        .buttonStyle(.plain)
}

private struct RefreshGoalRing: View {
    @Binding var goal: Int
    let japanese: Bool
    let haptics: Bool
    let commit: () -> Void
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                var arc = Path(); arc.addArc(center: RefreshGeometry.center, radius: 100, startAngle: .degrees(135), endAngle: .degrees(405), clockwise: false)
                // Compose the supplied normalized gradient matrix with the supplied local-to-window transform.
                let a = (-1.0833332539 - 1.1002979279) / (sqrt(2) * 224.9997)
                let b = (-1.0833332539 + 1.1002979279) / (sqrt(2) * 224.9997)
                let c = 0.5024956465 - a * RefreshGeometry.center.x - b * 106
                let start = CGPoint(x: -(b * RefreshGeometry.center.y + c) / a, y: RefreshGeometry.center.y)
                let norm = a*a + b*b
                let end = CGPoint(x: start.x + a/norm, y: start.y + b/norm)
                // Composite the specified alpha stops onto the specified white canvas in sRGB.
                // This avoids the generic-RGB bitmap pipeline changing pale-stop colors.
                let mid = Color(red: 0.4, green: 0.4 + 0.6*95/255, blue: 0.4 + 0.6*204/255)
                let pale = Color(red: 0.8, green: 0.8 + 0.2*95/255, blue: 0.8 + 0.2*204/255)
                context.stroke(arc, with: .linearGradient(Gradient(stops: [.init(color: RefreshDesign.blue, location: 0), .init(color: mid, location: 0.485576928), .init(color: pale, location: 1)]), startPoint: start, endPoint: end), style: StrokeStyle(lineWidth: 25, lineCap: .round))
            }
            Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 5)).frame(width: 25, height: 25).position(RefreshGeometry.marker(goal))
            RefreshRingInput(value: goal, label: japanese ? "今回の目標回数、最大30回" : "Repetitions, maximum 30", change: { RefreshHaptics.changed(from: goal,to: $0,channel: "reps",enabled: haptics); goal = $0 }, commit: commit)
        }.frame(width: 402, height: 370)
    }
}

private struct RefreshRingInput: NSViewRepresentable {
    let value: Int; let label: String; let change: (Int) -> Void; let commit: () -> Void
    final class Input: NSView {
        var value = 5; var change: (Int) -> Void = { _ in }; var commit: () -> Void = {}; var angle: Double?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let p = convert(point, from: superview)
            let r = hypot(p.x - RefreshGeometry.center.x, p.y - RefreshGeometry.center.y)
            return r >= 80 && r <= 125 ? self : nil
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); angle = RefreshGeometry.angle(value); update(event) }
        override func mouseDragged(with event: NSEvent) { update(event) }
        override func mouseUp(with event: NSEvent) { update(event); angle = nil; commit() }
        func update(_ event: NSEvent) { let result = RefreshGeometry.value(convert(event.locationInWindow, from: nil), previous: angle); angle = result.1; change(result.0) }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 123, 125: change(max(1, value - 1))
            case 124, 126: change(min(30, value + 1))
            case 115: change(1)
            case 119: change(30)
            default: super.keyDown(with: event); return
            }; commit()
        }
        override func accessibilityPerformIncrement() -> Bool { change(min(30, value + 1)); commit(); return true }
        override func accessibilityPerformDecrement() -> Bool { change(max(1, value - 1)); commit(); return true }
    }
    func makeNSView(context: Context) -> Input {
        let v = Input(); v.setAccessibilityElement(true); v.setAccessibilityRole(.slider); v.setAccessibilityMinValue(1); v.setAccessibilityMaxValue(30); return v
    }
    func updateNSView(_ view: Input, context: Context) {
        view.value = value; view.change = change; view.commit = commit
        view.setAccessibilityLabel(label); view.setAccessibilityValue(value)
    }
}

private struct RefreshWeek: View {
    @ObservedObject var history: WorkoutHistory
    let dates: Namespace.ID
    var body: some View {
        let calendar = ProgressCalendarModel.localCalendar(timeZone: history.calendarTimeZone)
        let today = calendar.startOfDay(for: history.currentDate)
        let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today)-1), to: today)!
        let labelXs: [CGFloat] = [62,111.5,160,208.5,257.5,303.5,348]
        let circleXs: [CGFloat] = [62.5,111.5,160.5,208.5,257.5,303.5,348.5]
        ZStack(alignment: .topLeading) {
            ForEach(0..<7) { i in
                let day = calendar.date(byAdding: .day, value: i, to: start)!
                let count = history.count(on: day)
                Text(["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][i]).font(RefreshDesign.font(16)).foregroundStyle(day == today ? .white : RefreshDesign.secondary).position(x: labelXs[i], y: 619.5)
                ZStack {
                    if count > 0 && day <= today {
                        Circle().fill(RefreshDesign.blue)
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .regular)).foregroundStyle(.white)
                    } else if day == today { Circle().fill(.white) }
                    else { Circle().stroke(.white, style: StrokeStyle(lineWidth: 1, dash: [2,2])) }
                }.frame(width: 25, height: 25).position(x: circleXs[i], y: 650.5)
                    .matchedGeometryEffect(id: calendar.startOfDay(for: day), in: dates)
                    .help("\(day.formatted(date: .complete, time: .omitted)) · \(count)")
                    .accessibilityElement(children: .ignore).accessibilityLabel("\(day.formatted(date: .complete, time: .omitted)), \(count)")
            }
        }
    }
}

private struct RefreshSettings: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var usage: RefreshUsageService
    let showAbout: () -> Void; let contact: () -> Void
    @State private var providerToAllow: AIProvider?
    @State private var allowExplanation = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.98)).frame(width: 362, height: 100).position(x: 201, y: 192)
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.98)).frame(width: 362, height: 157).position(x: 201, y: 408.5)
            settingText(settings.t("AIアプリ", "AI Apps"), x: 30, y: 118)
            settingText(settings.t("ChatGPT / Codex", "ChatGPT / Codex"), x: 36, y: 161)
            settingText(settings.t("Claude", "Claude"), x: 36, y: 204)
            RefreshSwitch(isOn: providerBinding(.chatgptDesktop)).position(x: 338, y: 170).accessibilityLabel("ChatGPT / Codex")
            RefreshSwitch(isOn: providerBinding(.claudeDesktop)).position(x: 338, y: 213).accessibilityLabel("Claude")
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.98)).frame(width: 362, height: 44).position(x: 201, y: 276)
            settingText(settings.t("PC利用時間", "Desk time"), x: 36, y: 266)
            RefreshSwitch(isOn: $settings.deskCollectionAllowed).position(x: 338, y: 275.5)
                .accessibilityLabel(settings.t("PC利用時間を集計する", "Count active PC time"))
                .accessibilityIdentifier("refresh.deskTime")
                .help(settings.t("Squat起動中の有効なPC利用時間を集計します。AI利用を含みます。", "Count active PC time while Squat is running, including AI use."))
            settingText(settings.t("通知", "Notifications"), x: 30, y: 306)
            settingText(settings.t("通知", "Notifications"), x: 36, y: 349)
            RefreshSwitch(isOn: $settings.usageRemindersEnabled).position(x: 338, y: 358).accessibilityLabel(settings.t("通知", "Notifications"))
            settingText(settings.t("通知の間隔", "Reminder Interval"), x: 36, y: 392)
            Text(settings.isJapanese ? "\(settings.usageReminderInterval.rawValue)分" : "\(settings.usageReminderInterval.rawValue)m")
                .font(RefreshDesign.font(20)).frame(width: 58, height: 24, alignment: .leading).position(x: 65, y: 455)
            RefreshIntervalSlider(value: Binding(get: { settings.usageReminderInterval.rawValue }, set: { settings.usageReminderInterval = UsageReminderInterval(rawValue: $0) ?? .minutes60 }), japanese: settings.isJapanese, haptics: settings.hapticsEnabled)
                .offset(y: 44)
            settingText(settings.t("言語", "Language"), x: 30, y: 499)
            RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.98)).frame(width: 362, height: 44).position(x: 201, y: 548)
            HStack(spacing: 0) {
                language("日本語", .ja); language("English", .en)
            }.frame(width: 330, height: 28).position(x: 201, y: 548)
            HStack(spacing: 0) {
                Button(action: showAbout) { Text(settings.t("バージョン ", "Version ") + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")) }
                    .frame(width: 165, height: 26)
                Button(action: contact) { Text(settings.t("お問い合わせ", "Contact us")) }.frame(width: 165, height: 26)
            }.buttonStyle(.plain).font(RefreshDesign.font(16, japanese: settings.isJapanese)).position(x: 201, y: 595.5)

        }.frame(width: 402, height: 706)
            .confirmationDialog(settings.t("選択したアプリを前面にしている時間を集計します。", "Count selected apps while they are in front."), isPresented: $allowExplanation) {
                Button(settings.t("集計する", "Allow counting")) { settings.usageCollectionAllowed = true; if let p = providerToAllow { settings.selectedProviders.insert(p) } }
                Button(settings.t("キャンセル", "Cancel"), role: .cancel) { providerToAllow = nil }
            }
    }
    private func settingText(_ text: String, x: CGFloat, y: CGFloat) -> some View {
        Text(text).font(RefreshDesign.font(16, japanese: settings.isJapanese)).tracking(settings.isJapanese ? 0 : 0.32).frame(width: 258, height: 19, alignment: .leading).position(x: x + 129, y: y + 9.5)
    }
    private func providerBinding(_ provider: AIProvider) -> Binding<Bool> {
        Binding(get: { settings.selectedProviders.contains(provider) }, set: { on in
            if !on { settings.selectedProviders.remove(provider) }
            else if settings.usageCollectionAllowed { settings.selectedProviders.insert(provider) }
            else { providerToAllow = provider; allowExplanation = true }
        })
    }
    private func language(_ label: String, _ value: AppLanguage) -> some View {
        Button { settings.language = value } label: { Text(label).font(RefreshDesign.font(16, japanese: value == .ja)).frame(width: 165, height: 28).foregroundStyle(settings.language == value ? .white : .black).background(settings.language == value ? RefreshDesign.blue : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
    }
}


private struct RefreshSwitch: View {
    @Binding var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        Button { withAnimation(reduced ? nil : .easeOut(duration: 0.16)) { isOn.toggle() } } label: {
            Capsule().fill(isOn ? Color(red: 52/255, green: 199/255, blue: 89/255) : Color(white: 0.85))
                .overlay(alignment: .leading) { Capsule().fill(.white).frame(width: 38, height: 24).offset(x: isOn ? 24 : 2) }
                .frame(width: 64, height: 28).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityValue(isOn ? "On" : "Off").accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct RefreshIntervalSlider: View {
    @Binding var value: Int
    let japanese: Bool
    let haptics: Bool
    private let points = RefreshIntervalGeometry.points
    private let values = RefreshIntervalGeometry.values
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<5) { i in
                Rectangle().fill(Color(white: 185/255)).frame(width: 1, height: 19).position(x: points[i], y: 408.5)
                Text("\(values[i])").font(RefreshDesign.font(16)).position(x: points[i], y: 391.5)
            }
            Capsule().fill(Color(white: 0.85)).frame(width: 268, height: 19).position(x: 229, y: 413.5)
            Capsule().fill(RefreshDesign.blue).frame(width: RefreshIntervalGeometry.fillWidth(at: x), height: 19).position(x: 95+RefreshIntervalGeometry.fillWidth(at: x)/2, y: 413.5)
            Circle().fill(.white).overlay(Circle().stroke(.black, lineWidth: 3)).frame(width: 15, height: 15).position(x: x, y: 413.5)
            RefreshLinearInput(value: value, positions: points.map { $0-95 }, values: values, discrete: true, label: japanese ? "通知の間隔" : "Reminder interval", change: { RefreshHaptics.changed(from: value,to: $0,channel: "interval",enabled: haptics); value = $0 }, commit: {})
                .frame(width: 268, height: 35).position(x: 229, y: 413.5)
        }.frame(width: 402, height: 706)
    }
    private var x: CGFloat { points[values.firstIndex(of: value) ?? 1] }
}

private struct RefreshLinearInput: NSViewRepresentable {
    let value: Int
    let positions: [CGFloat]
    let values: [Int]
    let discrete: Bool
    let label: String
    let change: (Int) -> Void
    let commit: () -> Void
    final class Input: NSView {
        var value = 0; var positions: [CGFloat] = []; var values: [Int] = []; var discrete = true
        var change: (Int) -> Void = { _ in }; var commit: () -> Void = {}
        override var isOpaque: Bool { false }
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); update(event) }
        override func mouseDragged(with event: NSEvent) { update(event) }
        override func mouseUp(with event: NSEvent) { update(event); commit() }
        func update(_ event: NSEvent) {
            guard !positions.isEmpty else { return }
            let x = min(positions.last!,max(positions.first!,convert(event.locationInWindow,from: nil).x))
            if discrete {
                let i = positions.indices.min { abs(positions[$0]-x) < abs(positions[$1]-x) } ?? 0
                change(values[i]); return
            }
            let i = (0..<(positions.count-1)).first { x <= positions[$0+1] } ?? positions.count-2
            let fraction = Double(x-positions[i]) / Double(positions[i+1]-positions[i])
            let interpolated = Double(values[i]) + fraction * Double(values[i+1]-values[i])
            change(Int(interpolated.rounded()))
        }
        private func step(_ delta: Int) {
            if discrete { let i = values.firstIndex(of: value) ?? 0; change(values[min(values.count-1,max(0,i+delta))]) }
            else { change(min(values.last ?? 100,max(values.first ?? 0,value+delta))) }; commit()
        }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 123,125: step(-1)
            case 124,126: step(1)
            case 115: change(values.first ?? 0); commit()
            case 119: change(values.last ?? 100); commit()
            default: super.keyDown(with: event)
            }
        }
        override func accessibilityPerformIncrement() -> Bool { step(1); return true }
        override func accessibilityPerformDecrement() -> Bool { step(-1); return true }
    }
    func makeNSView(context: Context) -> Input {
        let v = Input(); v.wantsLayer = true; v.layer?.backgroundColor = NSColor.clear.cgColor
        v.setAccessibilityElement(true); v.setAccessibilityRole(.slider); return v
    }
    func updateNSView(_ view: Input, context: Context) {
        view.value = value; view.positions = positions; view.values = values; view.discrete = discrete; view.change = change; view.commit = commit
        view.setAccessibilityLabel(label); view.setAccessibilityValue(value); view.setAccessibilityMinValue(values.first); view.setAccessibilityMaxValue(values.last)
    }
}
