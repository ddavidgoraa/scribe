import AppKit

/// Visual styling of Markdown source. Typography is refined in M5 (iA fonts).
struct MarkdownTheme {
    var fontSize: CGFloat = 16

    var bodyFont: NSFont { .systemFont(ofSize: fontSize) }
    var monoFont: NSFont { .monospacedSystemFont(ofSize: fontSize * 0.9, weight: .regular) }

    func headingFont(level: UInt8) -> NSFont {
        let scale: [CGFloat] = [1.45, 1.3, 1.15, 1.05, 1, 1]
        let index = max(0, min(Int(level) - 1, scale.count - 1))
        return .systemFont(ofSize: (fontSize * scale[index]).rounded(), weight: .bold)
    }

    var textColor: NSColor { .labelColor }
    /// Syntax characters: visible but quiet, like iA Writer.
    var markerColor: NSColor { .tertiaryLabelColor }
    var secondaryColor: NSColor { .secondaryLabelColor }
    var linkColor: NSColor { .linkColor }
    var mathColor: NSColor { .systemIndigo }
    var codeBackground: NSColor { .quaternarySystemFill }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.25
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    /// Attributes that make source characters (nearly) invisible and zero-width.
    static var hiddenAttributes: [NSAttributedString.Key: Any] { [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ] }

    static let standard = MarkdownTheme()
}
