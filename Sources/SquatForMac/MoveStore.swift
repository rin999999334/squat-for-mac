import AppKit
import SwiftUI
import AVFoundation

enum RecognitionState { case idle, permission, starting, missing, calibrating, ready, moved, counted, complete, paused, error }

@MainActor final class MoveStore: ObservableObject {
    let camera = Camera()
    let history: WorkoutHistory
    private let defaults: UserDefaults
    @Published var showWorkout = false
    @Published var count = 0
    @Published var goal = 5
    @Published private(set) var sessionTarget = 5
    @Published private(set) var sessionID = UUID()
    @Published var issue: RecognitionIssue?
    @Published var active = false
    @Published var ready = false
    @Published var demo = false
    @Published var state: RecognitionState = .idle
    @Published var message = "準備ができたら、少し動いてみましょう。"
    @Published var angle: Double?
    @Published var looseMode = true
    @Published var faceBox: CGRect?
    @Published private(set) var faceFraming: FaceFramingStatus = .waitingForLayout
    @Published var cameraAspect = 4.0 / 3.0
    @Published var movement = 0.0
    @Published var calibrationProgress = 0.0
    @Published var preparing = true
    @Published var neutralY: Double?
    @Published var depthLines: FaceDepthLines?
    @Published var challengeReached = false
    @Published var lastRepAt: Date?
    @Published var startedAt: Date?
    @Published var finishedDuration = 0.0
    private var faceCounter = FaceMovementCounter()
    private var counter = SquatCounter()
    private var runID = UUID()
    private var timer: Timer?
    private var demoTime = 0.0
    var onGoalReached: (() -> Void)?
    var onStorageFailure: (() -> Void)?
    private var sessionMode = "顔の動き"
    private var cameraViewportSize: CGSize?

    init(defaults: UserDefaults = .standard, history: WorkoutHistory? = nil) {
        self.defaults = defaults
        self.history = history ?? WorkoutHistory(defaults: defaults)
        if defaults.object(forKey: "looseMode") != nil { looseMode = defaults.bool(forKey: "looseMode") }
        if let value = defaults.object(forKey: "sessionGoal") as? Int { goal = min(30, max(1, value)) }
        camera.onSample = { [weak self] value, side, id, time in
            guard let self, self.active, self.ready, !self.demo, !self.looseMode, self.runID == id else { return }
            self.accept(value, side: side, time: time)
        }
        camera.onFace = { [weak self] y, height, box, aspect, time, id, reason in
            guard let self, self.active, self.ready, self.looseMode, !self.demo, self.runID == id else { return }
            self.processFace(y: y, height: height, box: box, aspect: aspect, time: time, reason: reason)
        }
        camera.onError = { [weak self] issue, id in
            guard let self, self.active, !self.demo, self.runID == id else { return }
            self.stop(); self.state = .error; self.issue = issue; self.message = issue.japaneseText
        }
    }
    func saveSettings() {
        defaults.set(looseMode, forKey: "looseMode")
        defaults.set(min(30, max(1, goal)), forKey: "sessionGoal")
    }
    func visibleState(at now: Date) -> RecognitionState {
        if active, let lastRepAt, now.timeIntervalSince(lastRepAt) < 0.9, state == .ready || state == .moved { return .counted }
        return state
    }
    func duration(at now: Date) -> TimeInterval { active ? startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0 : finishedDuration }
    var preparationSecondsRemaining: Int { max(0, Int(ceil(WorkoutPreparation.duration * (1 - calibrationProgress)))) }
    func updateCameraViewport(_ size: CGSize) {
        let next: CGSize? = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? size : nil
        guard next != cameraViewportSize else { return }
        let hadLayout = cameraViewportSize != nil
        cameraViewportSize = next
        updateLineScale(aspect: cameraAspect)
        // A resize can crop away the old target. Reconfirm once, keeping reps;
        // ordinary downward motion never changes the established target.
        if hadLayout && active && ready && looseMode && !demo && !preparing { recalibrate() }
    }
    // Camera's run-ID guard remains at the callback boundary. This separate
    // handler also permits deterministic framing checks without opening a camera.
    func processFace(y: Double?, height: Double?, box: CGRect?, aspect: Double, time: Double, reason: RecognitionIssue? = nil) {
        guard active && ready && looseMode && !demo else { return }
        faceBox = box
        if cameraAspect != aspect {
            cameraAspect = aspect
            updateLineScale(aspect: aspect)
            if !preparing { recalibrate() }
        }
        if let box, y != nil, height != nil {
            let framing = FaceFraming.status(box: box, viewportSize: cameraViewportSize, aspect: aspect,
                                             preparing: preparing)
            if faceFraming != framing { faceFraming = framing }
            if framing != .ready {
                acceptFace(y: nil, height: nil, time: time)
                // A detected but poorly placed face has a positioning cue,
                // rather than incorrectly telling the user no face was detected.
                issue = nil
                return
            }
        } else {
            if faceFraming != .centerFace { faceFraming = .centerFace }
            acceptFace(y: nil, height: nil, time: time, reason: reason)
            return
        }
        acceptFace(y: y, height: height, time: time, reason: reason, x: box.map { Double($0.midX) }, aspect: aspect)
    }
    func start(demo: Bool = false, target: Int? = nil) {
        guard !active else { showWorkout = true; return }
        guard demo || history.canRecord else { issue = .storageFailed; state = .error; message = RecognitionIssue.storageFailed.japaneseText; return }
        saveSettings(); showWorkout = true
        sessionTarget = min(30, max(1, target ?? goal)); sessionID = UUID()
        sessionMode = looseMode ? "顔の動き" : "膝の角度"; issue = nil
        runID = UUID(); let id = runID
        count = 0; angle = nil; counter.reset(); faceBox = nil; movement = 0; calibrationProgress = 0; preparing = true; neutralY = nil; lastRepAt = nil
        startedAt = nil; finishedDuration = 0
        depthLines = nil; challengeReached = false
        updateLineScale(aspect: cameraAspect); faceCounter.reset()
        active = true; ready = false; self.demo = demo; state = .starting
        faceFraming = demo ? .ready : .waitingForLayout
        if demo {
            ready = true; demoTime = 0; state = .calibrating
            message = "カメラを使わず、動きの見本を再生しています。"
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.active, self.demo, self.runID == id else { return }
                    self.demoTime += 0.1
                    let movingTime = max(0, self.demoTime - (WorkoutPreparation.duration + 0.5))
                    let phase = movingTime.truncatingRemainder(dividingBy: 2.4)
                    if self.looseMode {
                        let previewPhase = movingTime.truncatingRemainder(dividingBy: 12)
                        if self.demoTime > WorkoutPreparation.duration + 0.5 && previewPhase >= 3.3 && previewPhase < 3.65 {
                            self.acceptFace(y: nil, height: nil, time: self.demoTime, reason: .noFace)
                            return
                        }
                        let lowerY = 0.6 - FaceDepthLines(baseline: 0.6, imageHeight: self.faceCounter.imageHeight).minimumDistance - 0.05
                        self.acceptFace(y: phase < 0.8 || phase >= 1.6 ? 0.6 : lowerY, height: 0.2, time: self.demoTime, x: 0.5)
                    } else { self.accept(phase < 0.8 || phase >= 1.6 ? 175 : 95, side: "デモ", time: self.demoTime) }
                }
            }
            return
        }
        message = "カメラを準備しています。"
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: openCamera(id: id)
        case .notDetermined:
            state = .permission; message = "表示されるカメラの許可を選んでください。"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.active, self.runID == id else { return }
                    if granted { self.openCamera(id: id) } else { self.permissionDenied() }
                }
            }
        default: permissionDenied()
        }
    }
    private func openCamera(id: UUID) {
        state = .starting
        camera.start(useFace: looseMode, runID: id) { [weak self] error in
            guard let self, self.active, self.runID == id else { return }
            if let error { self.stop(); self.state = .error; self.issue = error; self.message = error.japaneseText }
            else {
                self.ready = true; self.state = .missing
                self.message = self.looseMode ? "顔を中央に映すと、\(WorkoutPreparation.seconds)秒の準備が始まります。" : "横向きで腰・膝・足首を映してください。"
            }
        }
    }
    private func permissionDenied() {
        stop(); state = .error
        issue = .permissionDenied; message = RecognitionIssue.permissionDenied.japaneseText
    }
    private func accept(_ value: Double?, side: String?, time: Double) {
        angle = value
        let counted = counter.update(angle: value, side: side, time: time)
        calibrationProgress = counter.calibrationProgress; preparing = counter.phase == .calibrating
        if !preparing { beginCountingIfNeeded() }
        if counted, recordRep() { return }
        issue = value == nil ? .noBody : nil
        if value == nil { state = .missing; message = "腰・膝・足首が見える位置へ移動してください。" }
        else {
            switch counter.phase {
            case .calibrating: state = .calibrating; message = value! < 160 ? "まずまっすぐ立つと、\(WorkoutPreparation.seconds)秒の準備が始まります。" : "この位置で待つと、自動で始まります。"
            case .standing: state = .ready; message = "ゆっくりしゃがんでみましょう。"
            case .down: state = .moved; message = "立ち上がると1回です。"
            }
        }
    }
    private func recordRep() -> Bool {
        guard demo || history.canRecord else {
            stop(); state = .error; issue = .storageFailed; message = RecognitionIssue.storageFailed.japaneseText
            onStorageFailure?(); return true
        }
        guard count < sessionTarget else { return false }
        count += 1; lastRepAt = Date()
        if !demo { history.recordRep(at: history.currentDate, mode: sessionMode) }
        if count >= sessionTarget {
            let wasDemo = demo
            stop(completed: true); state = .complete
            message = wasDemo ? "デモ完了。今日の記録には含まれません。" : "目標達成！今日の記録に保存しました。"
            onGoalReached?()
            return true
        }
        return false
    }
    private func beginCountingIfNeeded() {
        guard startedAt == nil else { return }
        startedAt = Date()
        if !demo { history.beginSession(mode: sessionMode, at: history.currentDate) }
    }
    private func acceptFace(y: Double?, height: Double?, time: Double, reason: RecognitionIssue? = nil, x: Double? = nil, aspect: Double = 4.0 / 3.0) {
        let counted = faceCounter.update(y: y, height: height, time: time, x: x, aspect: aspect)
        movement = faceCounter.displacement; calibrationProgress = faceCounter.calibrationProgress; neutralY = faceCounter.baseline
        depthLines = faceCounter.depthLines; challengeReached = faceCounter.challengeReached
        preparing = faceCounter.phase == .calibrating
        if !preparing { beginCountingIfNeeded() }
        if counted, recordRep() { return }
        issue = y == nil ? reason ?? .noFace : nil
        if y == nil { state = .missing; movement = 0; message = issue!.japaneseText; return }
        switch faceCounter.phase {
        case .calibrating: state = .calibrating; message = "この位置で\(WorkoutPreparation.seconds)秒待つと、自動で始まります。"
        case .resting: state = .ready; message = "顔が上下に動くと反応します。"
        case .moved: state = .moved; message = "動きを検出！基準の高さに戻ると1回です。"
        }
    }
    /// Explicit review fixture only; never opens a camera or writes real history.
    func configureCameraReviewState(_ name: String) {
        guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", demo else { return }
        timer?.invalidate(); timer = nil
        ready = true; preparing = name == "prepare"; startedAt = Date(); count = 7
        state = preparing ? .calibrating : name == "missing" ? .missing : name == "end" || name == "challenge" ? .moved : .ready
        issue = name == "missing" ? .noFace : nil
        depthLines = preparing || name == "missing" ? nil : FaceDepthLines(baseline: 0.74,imageHeight: 706)
        challengeReached = name == "challenge"
        if name == "counted" { lastRepAt = Date().addingTimeInterval(1) }
    }
    /// Changes this session only; camera recognition and next-session preferences stay intact.
    func adjustSessionTarget(by delta: Int) {
        guard active, ready, state != .error, demo || history.canRecord else { return }
        sessionTarget = min(30, max(max(1, count + 1), sessionTarget + (delta < 0 ? -1 : 1)))
    }
    func recalibrate() {
        guard active && ready else { return }
        faceCounter.reset(); counter.reset(); movement = 0; calibrationProgress = 0; preparing = true; neutralY = nil; depthLines = nil; challengeReached = false; lastRepAt = nil
        if demo { demoTime = 0 }
        state = .calibrating; message = "今の位置で\(WorkoutPreparation.seconds)秒待つと、再開します。回数はそのまま残ります。"
    }
    private func updateLineScale(aspect: Double) {
        guard let size = cameraViewportSize else { return }
        faceCounter.imageHeight = Double(CameraViewport(size: size, aspect: aspect,
                                                        contentMode: CameraViewport.workoutContentMode).imageRect.height)
    }
    func stop(completed: Bool = false) {
        if active {
            finishedDuration = duration(at: Date())
            if !demo { history.finishSession(completed: completed, at: history.currentDate) }
        }
        runID = UUID(); active = false; ready = false
        timer?.invalidate(); timer = nil
        camera.stop(); counter.reset(); faceCounter.reset(); angle = nil; faceBox = nil; movement = 0; neutralY = nil; depthLines = nil; calibrationProgress = 0; preparing = true
    }
    func cancel() { stop(); state = .paused; message = "ここまでの回数は保存しました。いつでも再開できます。" }
}
