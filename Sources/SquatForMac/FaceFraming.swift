import Foundation
import CoreGraphics

enum FaceFramingStatus: Equatable {
    case waitingForLayout, centerFace, moveBack, moveUp, moveDown, ready
}

/// Eligibility is evaluated in the same cropped coordinate space as the preview.
/// Preparation reserves room for the face to reach the minimum, then freezes the
/// counter's original baseline. During exercise only current visibility is gated.
enum FaceFraming {
    static func status(box: CGRect, viewportSize: CGSize?, aspect: Double,
                       preparing: Bool) -> FaceFramingStatus {
        guard let size = viewportSize, size.width.isFinite, size.height.isFinite,
              size.width >= 40, size.height >= 240 else { return .waitingForLayout }
        guard [box.minX, box.minY, box.width, box.height].allSatisfy({ $0.isFinite }),
              box.width > 0, box.height > 0, box.minX >= 0, box.maxX <= 1,
              box.minY >= 0, box.maxY <= 1 else { return .centerFace }
        let viewport = CameraViewport(size: size, aspect: aspect, contentMode: CameraViewport.workoutContentMode)
        let face = viewport.rect(for: box)
        // Text overlays must never create invisible detection dead zones.
        // Only actual image edges and space to reach the minimum matter.
        let safe = CGRect(x: 4, y: 4, width: size.width - 8, height: size.height - 8)
        // Vision detects the full sensor image. A little display-edge cropping
        // is normal: do not reject an otherwise trackable face for a cut corner.
        func visibleFraction(_ rect: CGRect) -> CGFloat {
            let intersection = rect.intersection(safe)
            guard !intersection.isNull else { return 0 }
            return max(0, intersection.width * intersection.height) / (rect.width * rect.height)
        }
        guard visibleFraction(face) >= 0.55 else {
            if face.width > safe.width || face.height > safe.height { return .moveBack }
            if face.midY < safe.minY { return .moveDown }
            if face.midY > safe.maxY { return .moveUp }
            return .centerFace
        }
        if preparing {
            let lines = FaceDepthLines(baseline: Double(box.midY), imageHeight: Double(viewport.imageRect.height))
            // A target beyond the sensor's bottom edge cannot be reached with
            // the same detectable face box, even if a cropped preview looks usable.
            if lines.minimumY < Double(box.height) / 2 { return .moveUp }
            let downward = CGFloat(lines.minimumDistance) * viewport.imageRect.height
            if visibleFraction(face.offsetBy(dx: 0, dy: downward)) < 0.55 { return .moveUp }
        }
        return .ready
    }
}
