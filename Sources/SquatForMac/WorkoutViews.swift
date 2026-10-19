import SwiftUI
import AVFoundation

/// The original window is entirely camera content. Only edge-aligned text and
/// outline controls are overlaid; the face and central movement area stay clear.
struct SquatWorkoutView: View {
    @ObservedObject var coordinator: AppCoordinator
    @ObservedObject var store: MoveStore
    @ObservedObject var settings: AppSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let startColor = Color(red: 0,green: 1,blue: 21/255)
    private let endColor = Color(red: 1,green: 10/255,blue: 10/255)
    private let challengeColor = Color(red: 251/255,green: 200/255,blue: 0)
    private var borderColor: Color {
        guard store.ready, !store.preparing, store.issue == nil, store.state == .ready || store.state == .moved else { return Color(white: 0.7) }
        if store.challengeReached { return challengeColor }
        return store.state == .moved ? endColor : startColor
    }
    var body: some View {
        TimelineView(.periodic(from: .now,by: 0.1)) { context in
            let state = store.visibleState(at: context.date)
            ZStack(alignment: .topLeading) {
                SquatCameraStage(store: store,settings: settings).allowsHitTesting(false)
                HStack(alignment: .firstTextBaseline,spacing: 0) {
                    outlined(String(format: "%02d",store.count),size: 96)
                    outlined("/\(store.sessionTarget)",size: 36)
                }.frame(width: 350,height: 115).position(x: 201,y: 67.5).allowsHitTesting(false)
                    .accessibilityElement(children: .ignore).accessibilityLabel(settings.t("\(store.count)回、今回の目標\(store.sessionTarget)回", "\(store.count) repetitions, this target \(store.sessionTarget)"))
                if store.preparing && store.state == .calibrating {
                    outlined("\(store.preparationSecondsRemaining)",size: 48).position(x: 201,y: 480)
                }
                VStack(spacing: 4) {
                    outlined(state == .counted ? settings.t("いいですね！", "Good Job !!") : statusTitle(state),size: state == .counted ? 48 : 32)
                    if state != .counted {
                        if showsPositioningGuide(state) {
                            outlined(statusDetail(state),size: 16).multilineTextAlignment(.center).fixedSize(horizontal: false,vertical: true)
                        } else { outlined(statusDetail(state),size: 16) }
                    }
                    if state == .error { Button(settings.t("再試行", "Try again")) { coordinator.start(demo: store.demo) }.buttonStyle(.borderedProminent) }
                }.frame(width: 362,height: showsPositioningGuide(state) ? 96 : 78).position(x: 201.5,y: showsPositioningGuide(state) ? 589.5 : 602.5)
                control("arrow.left",label: "Home",x: 35) { coordinator.goHome() }
                control("arrow.triangle.2.circlepath",label: settings.t("カメラ位置を再調整", "Recalibrate"),x: 75,disabled: !store.active || !store.ready) { store.recalibrate() }
                control("minus",label: settings.t("今回の目標を減らす", "Decrease this target"),x: 327,disabled: !targetEditable || store.sessionTarget <= max(1,store.count+1)) { adjust(-1) }
                control("plus",label: settings.t("今回の目標を増やす", "Increase this target"),x: 367,disabled: !targetEditable || store.sessionTarget >= 30) { adjust(1) }
                if store.demo { outlined(settings.t("デモ · 記録されません", "DEMO · Not recorded"),size: 12).position(x: 201,y: 694) }
            }.frame(width: 402,height: 706).background(.black).clipShape(RoundedRectangle(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(borderColor,lineWidth: 2.5).allowsHitTesting(false).animation(reduceMotion ? nil : .easeOut(duration: 0.12),value: borderColor) }
                .onAppear { store.updateCameraViewport(CGSize(width: 402,height: 706)) }
        }
    }
    private var targetEditable: Bool { store.active && store.ready && store.state != .error && (store.demo || store.history.canRecord) }
    private func adjust(_ delta: Int) { let old = store.sessionTarget; store.adjustSessionTarget(by: delta); RefreshHaptics.changed(from: old,to: store.sessionTarget,channel: "reps",enabled: settings.hapticsEnabled) }
    private func control(_ icon: String,label: String,x: CGFloat,disabled: Bool = false,action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 16)).foregroundStyle(.white).frame(width: 30,height: 30).background(RefreshDesign.blue,in: Circle()).frame(width: 40,height: 40).contentShape(Rectangle()) }
            .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.4 : 1).position(x: x,y: 661).accessibilityLabel(label)
    }
    private func outlined(_ text: String,size: CGFloat) -> some View {
        Text(text).font(RefreshDesign.font(size,medium: true,japanese: settings.isJapanese)).foregroundStyle(.black)
            .shadow(color: .white,radius: 0,x: -1.25,y: 0).shadow(color: .white,radius: 0,x: 1.25,y: 0)
            .shadow(color: .white,radius: 0,x: 0,y: -1.25).shadow(color: .white,radius: 0,x: 0,y: 1.25)
    }

    private func statusTitle(_ state: RecognitionState) -> String {
        switch state {
        case .permission: return settings.t("カメラを許可", "Allow camera")
        case .starting: return settings.t("カメラ準備中…", "Starting camera…")
        case .missing:
            guard store.looseMode else { return settings.t("脚を映そう", "Show your legs") }
            if store.issue != nil { return settings.t("顔を映そう", "Show your face") }
            switch store.faceFraming {
            case .moveBack: return settings.t("少し後ろへ", "Step back")
            case .moveUp: return settings.t("顔を少し上へ", "Move higher")
            case .moveDown: return settings.t("顔を少し下へ", "Move lower")
            case .waitingForLayout: return settings.t("準備中…", "Preparing…")
            case .centerFace, .ready: return settings.t("中央に映そう", "Move to center")
            }
        case .calibrating: return settings.t("そのまま3秒", "Stay still")
        case .ready: return settings.t("ゆっくり下がる", "Move down")
        case .moved: return settings.t("立ち上がる", "Stand up")
        case .counted: return settings.t("いいですね！", "That's one!")
        case .complete: return settings.t("目標達成", "Set complete")
        case .error: return settings.t("確認しよう", "Let's check")
        case .idle, .paused: return settings.t("停止中", "Paused")
        }
    }

    private func showsPositioningGuide(_ state: RecognitionState) -> Bool {
        guard store.looseMode, store.preparing else { return false }
        switch state {
        case .starting, .calibrating: return true
        case .missing: return store.issue == nil || store.issue == .noFace
        default: return false
        }
    }
    private func statusDetail(_ state: RecognitionState) -> String {
        if showsPositioningGuide(state) {
            return settings.t("上半身全体が映る位置まで下がり、\nそのまま動かずに3秒お待ちください。",
                              "Step back until your whole upper body is in view.\nThen stand still for 3 seconds.")
        }
        if let issue = store.issue { return settings.t(issue.japaneseText, issue.englishText) }
        if state == .missing && store.looseMode && !store.demo {
            switch store.faceFraming {
            case .waitingForLayout: return settings.t("カメラ画面を準備しています", "Preparing the camera view")
            case .centerFace: return settings.t("顔が見える位置へ", "Move where your face is visible")
            case .moveBack: return settings.t("少し後ろへ下がってください", "Take a small step back")
            case .moveUp: return settings.t("顔を少し上へ。下に余白を", "Move slightly higher; leave room below")
            case .moveDown: return settings.t("顔を少し下へ動かしてください", "Move your face slightly lower")
            case .ready: break
            }
        }
        switch state {
        case .calibrating: return store.looseMode ? settings.t("立った姿勢で待ちます", "Stand still and upright") : settings.t("横向きで、まっすぐ立ちます", "Stand upright, facing sideways")
        case .ready: return store.looseMode ? settings.t("顔の中心を最低ラインへ", "Face center past the minimum") : settings.t("無理のない深さまで下がります", "Lower to a comfortable depth")
        case .moved: return settings.t("戻るラインを越えると1回", "Cross return to count one")
        case .permission: return settings.t("表示されるMacの確認でカメラを許可してください。", "Choose Allow in the Mac camera permission prompt.")
        case .error: return settings.t("カメラを確認して、再試行してください。", "Check the camera and try again.")
        case .missing: return store.looseMode ? settings.t("脚は映らなくても大丈夫です。", "Your legs can stay out of frame.") : settings.t("腰・膝・足首をカメラに映してください。", "Keep your hip, knee and ankle visible.")
        default: return ""
        }
    }
}

private struct WorkoutOutlineButton: ButtonStyle {
    var horizontalPadding: CGFloat = 17
    var minimumHeight: CGFloat = 44
    var fontSize: CGFloat = 16
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SquatDesign.ui(fontSize, weight: .semibold)).foregroundStyle(.white)
            .padding(.horizontal, horizontalPadding).frame(minHeight: minimumHeight)
            .background(SquatDesign.blue, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct SquatCameraStage: View {
    @ObservedObject var store: MoveStore
    @ObservedObject var settings: AppSettings
    private let unmet = Color(red: 1, green: 0.35, blue: 0.35)

    var body: some View {
        GeometryReader { geometry in
            let viewport = CameraViewport(size: geometry.size, aspect: store.cameraAspect, contentMode: CameraViewport.workoutContentMode)
            let state = store.visibleState(at: Date())
            let reached = state == .moved || state == .counted || state == .complete
            let feedback = reached ? SquatDesign.blue : unmet
            ZStack {
                Color.black
                if store.active && store.ready && !store.demo {
                    SquatCameraPreview(session: store.camera.session)
                } else if store.demo {
                    Rectangle().fill(Color(white: 0.12))
                        .frame(width: viewport.imageRect.width, height: viewport.imageRect.height)
                        .position(x: viewport.imageRect.midX, y: viewport.imageRect.midY)
                    Image(systemName: "figure.strengthtraining.functional")
                        .font(.system(size: min(geometry.size.width * 0.28, 160), weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.35))
                }
                if store.active && store.ready && store.looseMode {
                    if let lines = store.depthLines {
                        guide("Start", y: viewport.point(x: 0.5, y: lines.returnY).y, rect: viewport.visibleRect, color: Color(red: 0,green: 1,blue: 21/255), dashed: false)
                        guide("End", y: viewport.point(x: 0.5, y: lines.minimumY).y, rect: viewport.visibleRect, color: Color(red: 1,green: 10/255,blue: 10/255), dashed: false)
                        guide("Challenge", y: viewport.point(x: 0.5, y: lines.challengeY).y, rect: viewport.visibleRect, color: Color(red: 251/255,green: 200/255,blue: 0), dashed: false)
                    }
                    if let box = store.faceBox {
                        let rect = viewport.rect(for: box)
                        let faceFeedback = store.preparing && store.faceFraming == .ready ? SquatDesign.blue : feedback
                        RoundedRectangle(cornerRadius: 5).stroke(faceFeedback, lineWidth: 2.5)
                            .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped().allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(settings.t("画面いっぱいのカメラ映像", "Edge-to-edge camera preview"))
            .accessibilityIdentifier("workout.camera")
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
    }

    @ViewBuilder private func guide(_ title: String, y: CGFloat, rect: CGRect, color: Color, dashed: Bool, trailing: Bool = false) -> some View {
        if y >= rect.minY && y <= rect.maxY {
            ZStack(alignment: .topLeading) {
                let line = Path { path in path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y)) }
                let dash: [CGFloat] = dashed ? (trailing ? [12, 7] : [5, 5]) : []
                line.stroke(color, style: StrokeStyle(lineWidth: 3, dash: dash))
                Text(title).font(RefreshDesign.font(24,medium: true)).foregroundStyle(color)
                    .frame(width: 360,height: 29,alignment: .leading).position(x: 193,y: y-19)
            }
            .allowsHitTesting(false)
        }
    }
}
private struct SquatCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    final class PreviewView: NSView {
        let preview = AVCaptureVideoPreviewLayer()
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            preview.videoGravity = CameraViewport.workoutContentMode == .fill ? .resizeAspectFill : .resizeAspect
            layer?.addSublayer(preview)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            preview.frame = bounds
            if let connection = preview.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
            CATransaction.commit()
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.preview.session = session
        return view
    }
    func updateNSView(_ view: PreviewView, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
    }
}
