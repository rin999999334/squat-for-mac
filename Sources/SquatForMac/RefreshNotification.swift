import AppKit
import SwiftUI
import CoreText

enum RefreshDesign {
    static let blue = Color(red: 0, green: 95/255, blue: 204/255)
    static let countdownRed = Color(red: 238/255, green: 94/255, blue: 94/255)
    static let secondary = Color(white: 0.8)
    static func font(_ size: CGFloat, medium: Bool = false, japanese: Bool = false, bold: Bool = false) -> Font {
        if japanese { return .system(size: size, weight: bold ? .bold : medium ? .medium : .regular) }
        let name = bold ? ".SFCompactRounded-Bold" : medium ? ".SFCompactRounded-Medium" : ".SFCompactRounded-Regular"
        if let descriptor = compactDescriptors.first(where: { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name }) {
            return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
        }
        return .system(size: size, weight: bold ? .bold : medium ? .medium : .regular, design: .rounded)
    }
    private static let compactDescriptors = CTFontManagerCreateFontDescriptorsFromURL(URL(fileURLWithPath: "/System/Library/Fonts/SFCompactRounded.ttf") as CFURL) as? [CTFontDescriptor] ?? []
}

@MainActor final class RefreshNotificationPanel {
    private var panel: NSPanel?
    private var id: UUID?
    private var lifetime: RefreshNotificationLifetime?
    func show(_ item: RefreshInvitation, settings: AppSettings, onStart: @escaping (UUID) -> Void, onDismiss: @escaping (UUID) -> Void, onExpired: @escaping (UUID) -> Void) -> Bool {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main,
              screen.visibleFrame.width >= 400, screen.visibleFrame.height >= 100 else { return false }
        hide()
        let panel = RefreshPassivePanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let lifetime = RefreshNotificationLifetime(item: item)
        if Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27",
           let appearance = CommandLine.arguments.first(where: { $0.hasPrefix("--review-appearance=") }) {
            panel.appearance = NSAppearance(named: appearance.hasSuffix("dark") ? .darkAqua : .aqua)
        }
        panel.contentView = NSHostingView(rootView: RefreshNotificationCard(item: item, lifetime: lifetime, settings: settings, start: { onStart(item.id) }, dismiss: { onDismiss(item.id) }))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 416, y: screen.visibleFrame.maxY - 116))
        self.panel = panel; self.lifetime = lifetime; id = item.id; panel.orderFrontRegardless()
        lifetime.start { [weak self] in
            guard self?.id == item.id else { return }
            self?.hide(); onExpired(item.id)
        }
        return true
    }
    func hide() { lifetime?.stop(); lifetime = nil; panel?.orderOut(nil); panel = nil; id = nil }
}
private final class RefreshPassivePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct RefreshNotificationCard: View {
    let item: RefreshInvitation
    @ObservedObject var lifetime: RefreshNotificationLifetime
    @ObservedObject var settings: AppSettings
    let start: () -> Void
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @State private var hovered = false
    @State private var appeared = false
    var body: some View {
        let remaining = lifetime.timeline.remaining(at: lifetime.now)
        let endingOpacity = lifetime.timeline.opacity(at: lifetime.now)
        return Group {
            ZStack(alignment: .topLeading) {
                Button { if remaining > 0 { start() } } label: {
                    ZStack(alignment: .topLeading) {
                        material
                        if item.style == .primary {
                            label(item.source, size: 16, rect: CGRect(x: 53,y: 19,width: 277,height: 19))
                            label(RefreshGeometry.duration(item.seconds), size: 48, medium: true, rect: CGRect(x: 53,y: 37,width: 171,height: 57))
                            label("Do Squat", size: 16, medium: true, color: RefreshDesign.countdownRed, rect: CGRect(x: 287,y: 65,width: 65,height: 19))
                        } else {
                            label("Count down", size: 16, rect: CGRect(x: 53,y: 18,width: 214,height: 19))
                            label("Move now!!", size: 48, medium: true, rect: CGRect(x: 53,y: 37,width: 238,height: 57))
                            Path { p in p.addArc(center: CGPoint(x: 348,y: 48), radius: 36, startAngle: .degrees(90), endAngle: .degrees(90 + RefreshGeometry.countdownArc(reduced ? ceil(remaining) : remaining)), clockwise: false) }
                                .stroke(RefreshDesign.countdownRed, style: StrokeStyle(lineWidth: 7,lineCap: .butt))
                            Text("\(Int(ceil(remaining)))").font(RefreshDesign.font(40, medium: true)).foregroundStyle(RefreshDesign.countdownRed)
                                .frame(width: remaining > 9 ? 44 : 22,height: 48).position(x: 348,y: 48)
                                .accessibilityLabel(settings.t("残り\(Int(ceil(remaining)))秒", "\(Int(ceil(remaining))) seconds remaining"))
                        }
                        Circle().fill(RefreshDesign.countdownRed).frame(width: 30,height: 30).position(x: 28,y: 28)
                        Image(systemName: "bell").font(.system(size: 16,weight: .medium)).foregroundStyle(.white).position(x: 28,y: 28)
                        Circle().fill(RefreshDesign.countdownRed).frame(width: 30,height: 30).position(x: 375,y: 74)
                        Image(systemName: "arrow.right").font(.system(size: 16,weight: .medium)).foregroundStyle(.white).position(x: 375,y: 74)
                    }.frame(width: 400,height: 100).contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(RefreshNotificationButtonStyle()).disabled(remaining <= 0)
                    .accessibilityLabel(settings.t("スクワットを始める、目標\(item.target)回、\(item.source)", "Start squatting, target \(item.target), \(item.source)"))
                if hovered {
                    Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 20,height: 20).foregroundStyle(.primary).background(colorScheme == .dark ? Color(white: 0.15) : .white,in: Circle()) }
                        .buttonStyle(.plain).position(x: 386,y: 13).accessibilityLabel(settings.t("閉じる", "Close"))
                }
            }.frame(width: 400,height: 100).clipShape(RoundedRectangle(cornerRadius: 12))
                // Opacity is sampled from the same clock that closes the panel. No competing exit animation.
                .opacity(appeared ? endingOpacity : 0)
                .offset(y: reduced || appeared ? 0 : -4)
                .onHover { hovered = $0 }.onAppear { withAnimation(reduced ? nil : .easeOut(duration: 0.16)) { appeared = true } }
                .onExitCommand(perform: dismiss)
        }.frame(width: 400,height: 100)
    }
    @ViewBuilder private var material: some View {
        if opaque { RoundedRectangle(cornerRadius: 12).fill(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.94)) }
        else if #available(macOS 26.0, *) {
            RoundedRectangle(cornerRadius: 12).fill(.clear).glassEffect(.regular, in: .rect(cornerRadius: 12))
        } else { RefreshLegacyGlass() }
    }
    private func label(_ value: String, size: CGFloat, medium: Bool = false, color: Color = .primary, rect: CGRect) -> some View {
        Text(value).font(RefreshDesign.font(size,medium: medium)).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.7)
            .frame(width: rect.width,height: rect.height,alignment: .topLeading).position(x: rect.midX,y: rect.midY)
    }
}
/// Disabling at zero must block activation without dimming the held card.
private struct RefreshNotificationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
private struct RefreshLegacyGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
