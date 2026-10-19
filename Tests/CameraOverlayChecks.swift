import Foundation
import CoreGraphics

@main enum CameraOverlayChecks {
    static func main() {
        var checked = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) { precondition(condition(), message); checked += 1 }
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.00001 }
        func sameRect(_ lhs: CGRect, _ rhs: CGRect) -> Bool { close(lhs.minX, rhs.minX) && close(lhs.minY, rhs.minY) && close(lhs.width, rhs.width) && close(lhs.height, rhs.height) }
        check(CameraViewport.workoutContentMode == .fill, "The workout preview and its overlays share aspect-fill")
        for (name, size, aspect) in [
            ("small portrait", CGSize(width: 340, height: 560), 4.0 / 3.0),
            ("wide fullscreen", CGSize(width: 1440, height: 900), 4.0 / 3.0),
            ("widescreen camera", CGSize(width: 1440, height: 900), 16.0 / 9.0),
            ("matching image", CGSize(width: 1280, height: 720), 16.0 / 9.0),
            ("ultrawide desktop", CGSize(width: 3440, height: 1440), 4.0 / 3.0),
            ("ultrawide camera in portrait", CGSize(width: 800, height: 1280), 21.0 / 9.0),
            ("portrait camera on desktop", CGSize(width: 1440, height: 900), 9.0 / 16.0)
        ] {
            let viewport = CameraViewport(size: size, aspect: aspect, contentMode: CameraViewport.workoutContentMode)
            let rect = viewport.imageRect
            check(rect.minX <= 0.00001 && rect.maxX >= size.width - 0.00001 && rect.minY <= 0.00001 && rect.maxY >= size.height - 0.00001, "\(name): every window edge is covered without black bars")
            check(close(rect.width / rect.height, aspect), "\(name): filling never stretches the camera image")
            check(close(rect.width, size.width) || close(rect.height, size.height), "\(name): fill applies the smallest scale that covers all edges")
            check(close(rect.midX, size.width / 2) && close(rect.midY, size.height / 2), "\(name): image cropping is symmetric")
            check(sameRect(viewport.visibleRect, CGRect(origin: .zero, size: size)), "\(name): guide labels use visible window bounds rather than cropped image edges")
            let topLeft = viewport.point(x: 0, y: 1), bottomRight = viewport.point(x: 1, y: 0)
            check(close(topLeft.x, rect.minX) && close(topLeft.y, rect.minY) && close(bottomRight.x, rect.maxX) && close(bottomRight.y, rect.maxY), "\(name): Vision points include exactly the displayed crop offset")
            let face = viewport.rect(for: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
            let midpoint = viewport.point(x: 0.25, y: 0.4)
            check(close(face.midX, midpoint.x) && close(face.midY, midpoint.y), "\(name): face rectangles and guide points share a transform")
            let faceTopLeft = viewport.point(x: 0.1, y: 0.6), faceBottomRight = viewport.point(x: 0.4, y: 0.2)
            check(close(face.minX, faceTopLeft.x) && close(face.minY, faceTopLeft.y) && close(face.maxX, faceBottomRight.x) && close(face.maxY, faceBottomRight.y), "\(name): face corners agree with the unmirrored Vision bounds")
            let left = viewport.point(x: 0.2, y: 0.5), right = viewport.point(x: 0.8, y: 0.5)
            check(left.x < size.width / 2 && right.x > size.width / 2 && close(left.x + right.x, size.width), "\(name): asymmetric subjects retain left/right orientation without a mirror")
        }
        let portrait = CameraViewport(size: CGSize(width: 340, height: 560), aspect: 4.0 / 3.0, contentMode: .fill)
        check(close(portrait.imageRect.minX, -203.333333333) && close(portrait.imageRect.width, 746.666666667) && close(portrait.imageRect.minY, 0), "Portrait fixture crops the actual 4:3 image horizontally rather than scaling overlays into 340x560")
        check(portrait.point(x: 0.25, y: 0.5).x < 0 && portrait.point(x: 0.75, y: 0.5).x > 340, "Cropped source features stay offscreen rather than drawing misleading face boxes inside the preview")
        check(close(portrait.visibleRect.minX + 43, 43), "Portrait guide labels remain 43pt from the visible edge")
        let wide = CameraViewport(size: CGSize(width: 1440, height: 900), aspect: 4.0 / 3.0, contentMode: .fill)
        check(sameRect(wide.imageRect, CGRect(x: 0, y: -90, width: 1440, height: 1080)), "Wide fullscreen fixture crops 90pt from top and bottom")
        check(close(wide.point(x: 0.5, y: 0.9).y, 18), "A guide near the source top includes the fullscreen vertical crop")
        for invalid in [Double.nan, .infinity, 0, -1] {
            let fallback = CameraViewport(size: CGSize(width: 340, height: 560), aspect: invalid, contentMode: CameraViewport.workoutContentMode)
            check(sameRect(fallback.imageRect, portrait.imageRect), "Invalid camera metadata falls back to a full-bleed 4:3 transform")
        }
        let fit = CameraViewport(size: CGSize(width: 340, height: 560), aspect: 4.0 / 3.0, contentMode: .fit)
        check(sameRect(fit.imageRect, CGRect(x: 0, y: 152.5, width: 340, height: 255)) && sameRect(fit.visibleRect, fit.imageRect), "Explicit fit remains available for uncropped geometry and existing callers")
        print("PASS: \(checked) window-filling camera overlay checks")
    }
}
