import AppKit
import SwiftUI

/// One native text layout; the outline is drawn before the black fill.
struct CameraInstructionText: NSViewRepresentable {
    let text: String
    let size: CGFloat
    var weight: NSFont.Weight = .regular
    var lineLimit = 0

    func makeNSView(context: Context) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.cell = CameraInstructionCell(textCell: "")
        label.isSelectable = false
        label.isEditable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.maximumNumberOfLines = lineLimit
        label.lineBreakMode = .byWordWrapping
        label.cell?.wraps = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: Context) {
        let base = NSFont(name: SquatResources.inter, size: size) ?? .systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.addingAttributes([.traits: [NSFontDescriptor.TraitKey.weight: weight.rawValue]])
        let font = NSFont(descriptor: descriptor, size: size) ?? base
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let value = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.black, .strokeColor: NSColor.white,
            .strokeWidth: max(5, 150 / size), .paragraphStyle: paragraph
        ])
        if label.attributedStringValue != value { label.attributedStringValue = value }
        label.maximumNumberOfLines = lineLimit
        label.setAccessibilityLabel(text)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: NSTextField, context: Context) -> CGSize? {
        guard label.attributedStringValue.length > 0 else { return .zero }
        let width = max(1, proposal.width ?? label.attributedStringValue.size().width + 6)
        let bounds = label.attributedStringValue.boundingRect(with: CGSize(width: max(1, width - 6), height: .greatestFiniteMagnitude),
                                                             options: [.usesLineFragmentOrigin, .usesFontLeading])
        let lineHeight = ceil((label.attributedStringValue.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.boundingRectForFont.height ?? size * 1.3)
        let height = lineLimit > 0 ? min(ceil(bounds.height), lineHeight * CGFloat(lineLimit)) : ceil(bounds.height)
        return CGSize(width: min(width, ceil(bounds.width) + 6), height: max(size + 4, height + 4))
    }
}

private final class CameraInstructionCell: NSTextFieldCell {
    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        guard attributedStringValue.length > 0 else { return }
        let outline = NSMutableAttributedString(attributedString: attributedStringValue)
        let range = NSRange(location: 0, length: outline.length)
        outline.addAttribute(.foregroundColor, value: NSColor.white, range: range)
        let fill = NSMutableAttributedString(attributedString: attributedStringValue)
        fill.removeAttribute(.strokeWidth, range: range)
        fill.removeAttribute(.strokeColor, range: range)
        let rect = titleRect(forBounds: cellFrame)
        let options: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        outline.draw(with: rect, options: options)
        fill.draw(with: rect, options: options)
    }
}
