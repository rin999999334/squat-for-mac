import Foundation
import CoreGraphics

@main enum PreparationChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checked += 1
        }
        var face = FaceMovementCounter()
        var count = 0
        for frame in 0...29 {
            if face.update(y: 0.6, height: 0.2, time: Double(frame) / 10, x: 0.5) { count += 1 }
        }
        check(face.phase == .calibrating && face.calibrationProgress > 0.95 && face.calibrationProgress < 1, "Preparation cannot end before 3 seconds")
        check(count == 0 && face.baseline == nil, "Preparation does not count movements or publish a premature baseline")
        check(!face.update(y: 0.6, height: 0.2, time: 3, x: 0.5) && face.phase == .resting, "3 stationary seconds start counting automatically")
        check(face.calibrationProgress == 1 && face.baseline == 0.6, "Stable baseline and completed countdown agree")

        var natural = FaceMovementCounter()
        for frame in 0...30 {
            _ = natural.update(y: frame.isMultiple(of: 2) ? 0.605 : 0.595, height: 0.2, time: Double(frame) / 10, x: 0.5)
        }
        check(natural.phase == .resting, "Small natural sway still completes preparation")

        var moved = FaceMovementCounter()
        for frame in 0...10 { _ = moved.update(y: 0.6, height: 0.2, time: Double(frame) / 10, x: 0.5) }
        _ = moved.update(y: 0.52, height: 0.2, time: 1.1, x: 0.5)
        check(moved.calibrationProgress == 0 && moved.phase == .calibrating, "Large vertical movement restarts the countdown")
        _ = moved.update(y: 0.52, height: 0.2, time: 1.2, x: 0.56)
        check(moved.calibrationProgress == 0, "Horizontal relocation also restarts preparation")
        _ = moved.update(y: 0.52, height: 0.28, time: 1.3, x: 0.56)
        check(moved.calibrationProgress == 0, "Moving toward the camera restarts preparation")

        var interrupted = FaceMovementCounter()
        for frame in 0...15 { _ = interrupted.update(y: 0.6, height: 0.2, time: Double(frame) / 10) }
        _ = interrupted.update(y: nil, height: nil, time: 1.6)
        _ = interrupted.update(y: 0.6, height: 0.2, time: 1.7)
        check(abs(interrupted.calibrationProgress - 0.5) < 0.00001, "A short missing frame pauses rather than advances preparation")
        for frame in 18...30 { _ = interrupted.update(y: 0.6, height: 0.2, time: Double(frame) / 10) }
        check(interrupted.phase == .calibrating, "Missing time cannot complete the countdown")
        _ = interrupted.update(y: 0.6, height: 0.2, time: 3.1)
        _ = interrupted.update(y: 0.6, height: 0.2, time: 3.2)
        check(interrupted.phase == .resting, "Countdown completes once the missing time is recovered")

        var lost = FaceMovementCounter()
        for frame in 0...10 { _ = lost.update(y: 0.6, height: 0.2, time: Double(frame) / 10) }
        _ = lost.update(y: nil, height: nil, time: 1.8)
        check(lost.phase == .calibrating && lost.calibrationProgress == 0, "Losing the face resets preparation")
        face.reset()
        check(face.phase == .calibrating && face.calibrationProgress == 0 && face.baseline == nil, "Retaking position requires a fresh countdown")

        var knee = SquatCounter()
        for frame in 0...29 { _ = knee.update(angle: 175, side: "左", time: Double(frame) / 10) }
        check(knee.phase == .calibrating, "Knee mode also waits the full 3 seconds")
        check(!knee.update(angle: 175, side: "左", time: 3) && knee.phase == .standing, "Knee preparation ends without adding a rep")
        knee.reset()
        for frame in 0...10 { _ = knee.update(angle: 175, side: "左", time: Double(frame) / 10) }
        _ = knee.update(angle: 100, side: "左", time: 1.1)
        check(knee.calibrationProgress == 0 && knee.phase == .calibrating, "Crouching during knee preparation restarts it")

        for fps in [15, 30] {
            var rate = FaceMovementCounter()
            for frame in 0...(3 * fps) { _ = rate.update(y: 0.6, height: 0.2, time: Double(frame) / Double(fps)) }
            check(rate.phase == .resting, "Preparation is based on seconds at different frame rates")
        }

        let portrait = CameraViewport(size: CGSize(width: 430, height: 780), aspect: 4.0 / 3.0)
        check(portrait.imageRect == CGRect(x: -305, y: 0, width: 1040, height: 780), "Portrait preview fills height and crops horizontal edges")
        check(portrait.point(x: 0.5, y: 0.5) == CGPoint(x: 215, y: 390), "Face center stays aligned with aspect-fill preview")
        let box = portrait.rect(for: CGRect(x: 0.45, y: 0.5, width: 0.1, height: 0.2))
        check(abs(box.midX - 215) < 0.001 && abs(box.minY - 234) < 0.001 && abs(box.height - 156) < 0.001, "Face box uses bottom-origin Vision coordinates after cropping")
        let wide = CameraViewport(size: CGSize(width: 1200, height: 600), aspect: 4.0 / 3.0)
        check(wide.imageRect == CGRect(x: 0, y: -150, width: 1200, height: 900), "Wide windows fill width and crop vertical edges")
        let matching = CameraViewport(size: CGSize(width: 640, height: 480), aspect: 4.0 / 3.0)
        check(matching.imageRect == CGRect(x: 0, y: 0, width: 640, height: 480), "Matching aspect ratio preserves the full image")
        print("PASS: \(checked) preparation and camera viewport checks")
    }
}
