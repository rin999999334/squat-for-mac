import SwiftUI
import AppKit
import CoreText

enum SquatResources {
    static var bundle: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
    static func url(_ name: String, extension ext: String, folder: String) -> URL? {
        bundle.url(forResource: name, withExtension: ext, subdirectory: folder)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Resources/\(folder)")
            ?? bundle.url(forResource: name, withExtension: ext)
    }
    static let logo: NSImage? = url("squat-logo", extension: "png", folder: "Images").flatMap(NSImage.init(contentsOf:))
    static let inter = register("Inter")
    static let expanded = register("ZalandoSansExpanded")
    private static func register(_ name: String) -> String {
        guard let url = url(name, extension: "ttf", folder: "Fonts") else { return name == "Inter" ? "Inter-Regular" : "ZalandoSansExpanded-Regular" }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first(where: { (CTFontDescriptorCopyAttribute($0, kCTFontStyleNameAttribute) as? String) == "Regular" }) ?? descriptors.first,
              let postScript = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return name }
        return postScript
    }
}

enum SquatDesign {
    static let blue = Color(red: 0, green: 95.0 / 255, blue: 204.0 / 255)
    static let ink = Color.black
    static let muted = Color(red: 137.0 / 255, green: 137.0 / 255, blue: 137.0 / 255)
    static let track = Color(red: 223.0 / 255, green: 235.0 / 255, blue: 248.0 / 255)
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .custom(SquatResources.inter, size: size).weight(weight) }
    static func number(_ size: CGFloat) -> Font { ui(size).monospacedDigit() }
    static func text(_ size: CGFloat, japanese: Bool = false) -> Font {
        japanese ? .system(size: size) : .custom(SquatResources.expanded, size: size).weight(.light)
    }
    static func heat(_ level: Int) -> Color {
        switch level {
        case 1: return Color(red: 204.0/255, green: 223.0/255, blue: 245.0/255)
        case 2: return Color(red: 153.0/255, green: 191.0/255, blue: 235.0/255)
        case 3: return Color(red: 102.0/255, green: 159.0/255, blue: 224.0/255)
        case 4: return Color(red: 51.0/255, green: 127.0/255, blue: 214.0/255)
        case 5: return blue
        default: return .white
        }
    }
}

enum SquatMotion {
    static let selection = Animation.easeOut(duration: 0.16)
    static let page = Animation.easeOut(duration: 0.18)
    static let press = Animation.easeOut(duration: 0.12)
}

struct SquatSegmentedControl<Option: Hashable>: View {
    let options: [Option]
    let selected: Option
    let title: (Option) -> String
    let identifier: (Option) -> String
    let select: (Option) -> Void
    var usesInterfaceFont = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: {
                    Text(title(option)).font(usesInterfaceFont ? SquatDesign.ui(11) : SquatDesign.text(9))
                        .foregroundStyle(selected == option ? .white : SquatDesign.muted)
                        .frame(maxWidth: .infinity).frame(height: 24)
                        .contentShape(Rectangle())
                        .background {
                            if selected == option {
                                RoundedRectangle(cornerRadius: 3).fill(SquatDesign.blue).frame(height: 15)
                                    .matchedGeometryEffect(id: "selection", in: selection)
                            }
                        }
                }.buttonStyle(.plain).accessibilityIdentifier(identifier(option))
                    .accessibilityAddTraits(selected == option ? .isSelected : [])
            }
        }.animation(reduceMotion ? nil : SquatMotion.selection, value: selected)
    }
}

struct SquatLogo: View {
    var width: CGFloat = 68
    var body: some View {
        Group {
            if let logo = SquatResources.logo { Image(nsImage: logo).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "figure.strengthtraining.functional").resizable().scaledToFit().foregroundStyle(SquatDesign.blue) }
        }.frame(width: width, height: width * 59 / 216).accessibilityLabel("Squat")
    }
}

struct SquatPrimaryButton: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(SquatDesign.ui(13)).foregroundStyle(.white)
            .padding(.horizontal, 24).frame(minHeight: 36)
            .background(SquatDesign.blue, in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

@MainActor
final class SquatHaptics {
    static let shared = SquatHaptics()
    private var lastTime: TimeInterval = -.infinity
    func goalChanged(enabled: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, now - lastTime >= 0.05 else { return }
        lastTime = now
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
