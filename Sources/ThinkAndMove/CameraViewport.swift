import Foundation
import CoreGraphics

/// Matches the preview layer and overlays for both centered fit and fill.
struct CameraViewport {
    enum ContentMode { case fit, fill }
    // The native preview and all overlay transforms use the same workout policy.
    static let workoutContentMode: ContentMode = .fill
    let bounds: CGRect
    let imageRect: CGRect
    var visibleRect: CGRect { imageRect.intersection(bounds) }

    init(size: CGSize, aspect: Double, contentMode: ContentMode = .fill) {
        bounds = CGRect(origin: .zero, size: size)
        let ratio = aspect.isFinite && aspect > 0 ? aspect : 4.0 / 3.0
        let height = contentMode == .fit ? min(size.height, size.width / ratio) : max(size.height, size.width / ratio)
        let width = height * ratio
        imageRect = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    func point(x: Double, y: Double) -> CGPoint {
        CGPoint(x: imageRect.minX + x * imageRect.width, y: imageRect.minY + (1 - y) * imageRect.height)
    }

    func rect(for box: CGRect) -> CGRect {
        CGRect(x: imageRect.minX + box.minX * imageRect.width,
               y: imageRect.minY + (1 - box.maxY) * imageRect.height,
               width: box.width * imageRect.width, height: box.height * imageRect.height)
    }
}
