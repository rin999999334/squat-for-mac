import Foundation
import CoreGraphics

@main enum FramingStoreChecks {
    @MainActor static func main() {
        let suite = "Squat.Framing.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = WorkoutHistory(defaults: defaults)
        let store = MoveStore(defaults: defaults, history: history)
        // Feed the real sample handler without starting a camera or its permissions.
        store.active = true; store.ready = true
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            if !value() { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
            checks += 1
        }
        var time = 0.0
        func frame(_ centerY: Double = 0.6, x: Double = 0.5, missing: RecognitionIssue? = nil) {
            let box = missing == nil ? CGRect(x: x - 0.07, y: centerY - 0.1, width: 0.14, height: 0.2) : nil
            store.processFace(y: box == nil ? nil : centerY, height: box == nil ? nil : 0.2,
                              box: box, aspect: 4.0 / 3.0, time: time, reason: missing)
            time += 0.1
        }
        frame()
        check(store.preparing && store.calibrationProgress == 0 && store.faceFraming == .waitingForLayout, "Even a detected face waits for the actual viewport")
        store.updateCameraViewport(CGSize(width: 360, height: 720))
        for _ in 0..<40 { frame(x: 0.1) }
        check(store.preparing && store.neutralY == nil && store.calibrationProgress == 0, "A cropped-away face never completes preparation")
        check(store.faceFraming == .centerFace && store.issue == nil, "A detected misplaced face has a positioning cue rather than a missing-face error")
        for _ in 0..<15 { frame() }
        let progress = store.calibrationProgress
        check(progress > 0 && progress < 1 && store.count == 0, "An eligible face starts the three-second countdown without counting")
        for _ in 0..<2 { frame(missing: .multipleFaces) }
        check(store.calibrationProgress == progress && store.issue == .multipleFaces, "Ambiguous detections pause preparation and retain their specific explanation")
        for _ in 0..<16 { frame() }
        check(store.preparing, "Invisible time is never credited toward the three-second countdown")
        for _ in 0..<4 { frame() }
        check(!store.preparing && store.neutralY == 0.6 && store.count == 0, "Three valid stable seconds establish the baseline before a repetition")
        let baseline = store.depthLines
        let originalViewport = CameraViewport(size: CGSize(width: 360, height: 720), aspect: 4.0 / 3.0, contentMode: CameraViewport.workoutContentMode)
        check(abs(originalViewport.point(x: 0.5, y: baseline?.minimumY ?? 0).y - originalViewport.point(x: 0.5, y: baseline?.baseline ?? 0).y - 120) < 0.00001, "The displayed minimum is fixed at 120pt below the detected standing center")
        check(abs(originalViewport.point(x: 0.5, y: baseline?.returnY ?? 0).y - originalViewport.point(x: 0.5, y: baseline?.baseline ?? 0).y - 40) < 0.00001 && abs(originalViewport.point(x: 0.5, y: baseline?.challengeY ?? 0).y - originalViewport.point(x: 0.5, y: baseline?.minimumY ?? 0).y - 40) < 0.00001, "Challenge sits half the Start-to-End distance below End (40/120/160pt)")
        for _ in 0..<12 { frame(0.40) }
        check(store.state == .moved && store.count == 0, "Crossing the minimum gives feedback but waits for the return")
        check(store.depthLines?.baseline == baseline?.baseline && store.depthLines?.minimumY == baseline?.minimumY, "The target does not follow the face while squatting")
        for _ in 0..<12 { frame() }
        check(store.count == 1, "A visible minimum-and-return cycle records exactly once")
        for _ in 0..<12 { frame(0.40) }
        for _ in 0..<9 { frame(x: 0.1) }
        check(store.preparing && store.count == 1 && store.depthLines == nil, "Losing the face outside the visible crop discards a pending rep and requests fresh preparation")
        for _ in 0..<32 { frame() }
        check(!store.preparing && store.count == 1, "Reappearing and preparing never manufactures a repetition")
        store.updateCameraViewport(CGSize(width: 340, height: 560))
        check(store.preparing && store.count == 1 && store.depthLines == nil, "A changed crop requests fresh preparation without losing repetitions")
        for _ in 0..<32 { frame() }
        check(!store.preparing && store.count == 1, "The new viewport completes the same stable confirmation")
        let resizedViewport = CameraViewport(size: CGSize(width: 340, height: 560), aspect: 4.0 / 3.0, contentMode: CameraViewport.workoutContentMode)
        let resizedLines = store.depthLines
        check(abs(resizedViewport.point(x: 0.5, y: resizedLines?.minimumY ?? 0).y - resizedViewport.point(x: 0.5, y: resizedLines?.baseline ?? 0).y - 120) < 0.00001 && abs(resizedViewport.point(x: 0.5, y: resizedLines?.returnY ?? 0).y - resizedViewport.point(x: 0.5, y: resizedLines?.baseline ?? 0).y - 40) < 0.00001, "Resizing changes normalized thresholds but preserves the rendered pixel intervals")
        store.updateCameraViewport(CGSize(width: 340, height: 560))
        check(!store.preparing, "Repeated layout callbacks with the same size never restart preparation")
        store.recalibrate()
        check(store.preparing && store.count == 1 && store.depthLines == nil, "Manual repositioning keeps the existing count and resets the target")
        for _ in 0..<32 { frame(0.85) }
        check(!store.preparing && store.neutralY == 0.85 && store.count == 1, "The former header dead zone can now complete preparation")
        store.recalibrate()
        for _ in 0..<32 { frame(0.35) }
        check(!store.preparing && store.neutralY == 0.35 && store.count == 1, "The former footer dead zone can now complete preparation")
        for _ in 0..<12 { frame(0.12) }
        for _ in 0..<12 { frame(0.35) }
        check(store.count == 2, "An eligible lower-position face can complete a real minimum-and-return cycle")
        store.recalibrate()
        for _ in 0..<32 { frame(x: 0.71) }
        check(!store.preparing && store.count == 2, "A partially cropped face can prepare near the displayed edge")
        for _ in 0..<12 { frame(0.35, x: 0.71) }
        for _ in 0..<12 { frame(x: 0.71) }
        check(store.count == 3, "A partially visible face can complete a cycle without an artificial edge dead zone")
        store.stop()
        check(!store.active && history.lifetimeReps == 3, "Only valid completed cycles reached the isolated real-history path")
        print("PASS: \(checks) framing-to-counter integration checks")
    }
}
