import AppKit
import SwiftUI

/// A passive invitation surface. It never opens the main window or camera.
/// The controller must recheck ReminderRuntime.accept before handling onStart.
@MainActor
final class ReminderInvitationPanel {
    private var panel: PassiveInvitationPanel?
    private var displayedID: UUID?

    func show(_ invitation: ReminderPresentation, isJapanese: Bool,
              onStart: @escaping (UUID) -> Void, onDismiss: @escaping (UUID) -> Void) {
        hide()
        let content = InvitationContent(kind: invitation.kind, target: invitation.target, isJapanese: isJapanese,
                                        start: { [weak self] in
                                            self?.hide(id: invitation.id)
                                            onStart(invitation.id)
                                        }, dismiss: { [weak self] in
                                            self?.hide(id: invitation.id)
                                            onDismiss(invitation.id)
                                        })
        let panel = PassiveInvitationPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 128),
                                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: content)
        // Keep the panel in a visible screen, without activating Squat or changing
        // the keyboard's current destination. In unsupported spaces, skip display.
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        guard visible.width >= 340, visible.height >= 128 else { return }
        panel.setFrameOrigin(NSPoint(x: min(max(visible.minX, visible.maxX - 356), visible.maxX - 340),
                                     y: min(max(visible.minY, visible.maxY - 144), visible.maxY - 128)))
        self.panel = panel
        displayedID = invitation.id
        let activeBefore = NSApp.isActive
        panel.orderFrontRegardless()
        PreviewDiagnostics.record("invitation-shown", values: ["kind": invitation.kind.rawValue, "target": invitation.target,
            "visible": panel.isVisible, "width": panel.frame.width, "height": panel.frame.height,
            "activeBefore": activeBefore, "activeAfter": NSApp.isActive])
    }

    func hide(id: UUID? = nil) {
        if let id, id != displayedID { return }
        panel?.orderOut(nil)
        panel = nil
        displayedID = nil
    }
}

private final class PassiveInvitationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct InvitationContent: View {
    let kind: ReminderInvitationKind
    let target: Int
    let isJapanese: Bool
    let start: () -> Void
    let dismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.functional").font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white).frame(width: 40, height: 40)
                .background(SquatDesign.blue, in: RoundedRectangle(cornerRadius: 10)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Squat").font(SquatDesign.ui(12, weight: .semibold)).foregroundStyle(.black)
                Text(isJapanese ? "ひと息入れて、\(target)回どうですか？" : "Time for a short break?")
                    .font(SquatDesign.ui(12)).foregroundStyle(.black).fixedSize(horizontal: false, vertical: true)
                if kind == .displayTest {
                    Text(isJapanese ? "通知の表示テスト" : "Notification display test").font(SquatDesign.ui(9)).foregroundStyle(SquatDesign.muted)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 0) {
                Button(isJapanese ? "\(target)回やる" : "Do \(target) squats", action: start)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                Divider()
                Button(isJapanese ? "今はしない" : "Not now", action: dismiss)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            }.font(SquatDesign.ui(11)).buttonStyle(.plain).foregroundStyle(SquatDesign.blue)
                .frame(width: 84).padding(.vertical, 4)
        }.padding(.leading, 16).padding(.trailing, 10).padding(.vertical, 14)
            .frame(width: 340, height: 128)
            .background(Color(white: 0.98), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(appeared ? 1 : 0).offset(x: appeared || reduceMotion ? 0 : 6)
            .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { appeared = true } }
    }
}
