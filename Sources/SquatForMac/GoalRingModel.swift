import Foundation
import CoreGraphics

/// Screen coordinates: left-bottom 135° to right-bottom 405°, through the top.
enum GoalRingModel {
    static let range = 1...30
    static func angle(for value: Int) -> Double { 135 + Double(min(30, max(1, value)) - 1) / 29 * 270 }
    static func point(for value: Int, center: CGPoint = CGPoint(x: 125, y: 125), radius: CGFloat = 110) -> CGPoint {
        let theta = angle(for: value) * .pi / 180
        return CGPoint(x: center.x + radius * cos(theta), y: center.y + radius * sin(theta))
    }
    static func value(at point: CGPoint, center: CGPoint = CGPoint(x: 125, y: 125), previousAngle: Double? = nil) -> (value: Int, angle: Double) {
        var angle = atan2(point.y - center.y, point.x - center.x) * 180 / .pi
        if let previousAngle {
            angle += round((previousAngle - angle) / 360) * 360
        } else {
            while angle < 135 { angle += 360 }
            if angle > 405 { angle = angle < 450 ? 405 : 135 }
        }
        let clamped = min(405, max(135, angle))
        return (min(30, max(1, 1 + Int(((clamped - 135) / 270 * 29).rounded()))), angle)
    }
}
