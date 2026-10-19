import Foundation
import CoreGraphics

@main enum FaceFramingChecks {
    static func main() {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message); checks += 1 }
        func status(_ box: CGRect, size: CGSize? = CGSize(width: 360, height: 720), aspect: Double = 4.0 / 3.0, preparing: Bool = true) -> FaceFramingStatus {
            FaceFraming.status(box: box, viewportSize: size, aspect: aspect, preparing: preparing)
        }
        let neutral = CGRect(x: 0.43, y: 0.50, width: 0.14, height: 0.20)
        check(status(neutral) == .ready, "A centered face has room to reach the minimum in a portrait window")
        check(status(neutral, size: nil) == .waitingForLayout, "No countdown before the real preview size is known")
        check(status(neutral, size: .zero) == .waitingForLayout, "Zero-sized layouts never start preparation")
        let hidden = CGRect(x: 0.05, y: 0.5, width: 0.14, height: 0.2)
        check(status(hidden) == .centerFace, "A face visible to the sensor but cropped from the window cannot start")
        check(status(CGRect(x: 0.4, y: 0.20, width: 0.2, height: 0.2)) == .ready, "Lower faces are eligible when the real movement path fits, regardless of footer text")
        check(status(CGRect(x: 0.43, y: 0.75, width: 0.14, height: 0.2)) == .ready, "Upper faces are eligible; the header never creates a detection dead zone")
        check(status(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)) == .moveBack, "A face mostly cropped out of the preview asks for more distance")
        let deep = CGRect(x: 0.43, y: 0, width: 0.14, height: 0.2)
        check(status(deep) == .moveUp && status(deep, preparing: false) == .ready, "Once calibrated, a valid downward movement does not require room for a second movement")
        check(status(hidden, preparing: false) == .centerFace, "A pending repetition cannot use a face outside the displayed crop")
        check(status(CGRect(x: 0.55, y: 0.5, width: 0.2, height: 0.2)) == .ready, "An edge-cropped face with sufficient visible area is still eligible")
        check(status(CGRect(x: 0.60, y: 0.5, width: 0.2, height: 0.2)) == .centerFace, "A face mostly outside the window still needs repositioning")
        check(status(CGRect(x: 0.43, y: -0.1, width: 0.14, height: 0.2)) == .centerFace, "Partially invalid sensor bounds are rejected")
        check(status(CGRect(x: CGFloat.nan, y: 0.5, width: 0.14, height: 0.2)) == .centerFace, "Nonfinite detection bounds cannot pass the gate")
        check(status(neutral, size: CGSize(width: 340, height: 560)) == .ready, "The minimum supported window still allows a normal face")
        check(status(neutral, size: CGSize(width: 1200, height: 700)) == .ready, "Wide crop uses the same visible-image transform")
        check(status(neutral, aspect: 16.0 / 9.0) == .ready, "A 16:9 camera can prepare in the same portrait window")
        check(status(neutral, aspect: 0.75) == .ready, "A portrait camera can prepare without stretching")
        check(status(neutral, aspect: .nan) == .ready, "Missing aspect metadata uses the preview's 4:3 fallback")
        let lower = CGRect(x: 0.43, y: 0.10, width: 0.14, height: 0.2)
        check(status(lower) == .moveUp && status(deep) == .moveUp, "Preparation asks for more room when the fixed 120pt path leaves the sensor")
        check(status(CGRect(x: 0.465, y: 0.55, width: 0.07, height: 0.1)) == .ready && status(CGRect(x: 0.395, y: 0.45, width: 0.21, height: 0.3)) == .ready, "Small and large centered faces can use the same fixed-distance preparation")
        for size in [CGSize(width: 360, height: 720), CGSize(width: 340, height: 560), CGSize(width: 1200, height: 700)] {
            let viewport = CameraViewport(size: size, aspect: 4.0 / 3.0, contentMode: CameraViewport.workoutContentMode)
            let lines = FaceDepthLines(baseline: 0.6, imageHeight: viewport.imageRect.height)
            let center = viewport.point(x: 0.5, y: 0.6)
            let minimum = viewport.point(x: 0.5, y: lines.minimumY)
            check(abs(minimum.y - center.y - 120) < 0.00001, "Framing and displayed crop preserve the fixed pixel path after resizing")
        }
        print("PASS: \(checks) face framing checks")
    }
}
