import SwiftUI
import AppKit

private struct GoalArc: Shape {
    var end: Double = 405
    var animatableData: Double { get { end } set { end = newValue } }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: 110, startAngle: .degrees(135), endAngle: .degrees(end), clockwise: false)
        return path
    }
}

struct GoalRing: View {
    @Binding var goal: Int
    let japanese: Bool
    let hapticsEnabled: Bool
    let start: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func setGoal(_ value: Int) {
        let safe = min(30, max(1, value))
        guard safe != goal else { return }
        goal = safe
        SquatHaptics.shared.goalChanged(enabled: hapticsEnabled)
    }
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                GoalArc().stroke(SquatDesign.blue, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                GoalArc(end: GoalRingModel.angle(for: goal)).stroke(SquatDesign.blue, style: StrokeStyle(lineWidth: 1, lineCap: .round))
                Circle().fill(.white).overlay(Circle().stroke(SquatDesign.blue, lineWidth: 1)).frame(width: 9, height: 9)
                    .position(GoalRingModel.point(for: goal))
                GoalRingInput(value: goal, label: japanese ? "今回の目標回数" : "Repetitions for this set", setValue: setGoal)
                Button(action: start) {
                    VStack(spacing: 1) {
                        Text("Tap to start").font(SquatDesign.ui(11))
                        Text("\(goal)").font(SquatDesign.number(64))
                        Text("times").font(SquatDesign.ui(11))
                    }.foregroundStyle(.white).frame(width: 150, height: 150).background(SquatDesign.blue, in: Circle())
                }.buttonStyle(.plain).accessibilityLabel(japanese ? "\(goal)回を開始" : "Start \(goal) repetitions")
                    .keyboardShortcut(.defaultAction)
            }.frame(width: 250, height: 250)
        }
    }
}

/// Only the annulus receives mouse events. The start button stays a separate hit target.
private struct GoalRingInput: NSViewRepresentable {
    let value: Int
    let label: String
    let setValue: (Int) -> Void
    final class InputView: NSView {
        var value = 5
        var changed: (Int) -> Void = { _ in }
        private var previousAngle: Double?
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            let local = convert(point, from: superview)
            let distance = hypot(local.x - bounds.midX, local.y - bounds.midY)
            return distance >= 94 && distance <= 126 ? self : nil
        }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); previousAngle = nil; update(event) }
        override func mouseDragged(with event: NSEvent) { update(event) }
        override func mouseUp(with event: NSEvent) { update(event); previousAngle = nil }
        private func update(_ event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            let result = GoalRingModel.value(at: point, center: CGPoint(x: bounds.midX, y: bounds.midY), previousAngle: previousAngle)
            previousAngle = result.angle
            changed(result.value)
        }
        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 126, 124, 24, 69: changed(min(30, value + 1))
            case 125, 123, 27, 78: changed(max(1, value - 1))
            case 116: changed(min(30, value + 5))
            case 121: changed(max(1, value - 5))
            case 115: changed(1)
            case 119: changed(30)
            default: super.keyDown(with: event)
            }
        }
        override func accessibilityPerformIncrement() -> Bool { changed(min(30, value + 1)); return true }
        override func accessibilityPerformDecrement() -> Bool { changed(max(1, value - 1)); return true }
    }
    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.slider)
        view.setAccessibilityMinValue(1)
        view.setAccessibilityMaxValue(30)
        return view
    }
    func updateNSView(_ view: InputView, context: Context) {
        view.value = value; view.changed = setValue
        view.setAccessibilityLabel(label); view.setAccessibilityValue(value)
    }
}
