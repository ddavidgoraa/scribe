import AppKit

/// Visual styling of Markdown source, iA Writer–like: one typeface, a ~64 character
/// column, generous line height, quiet markers.
struct MarkdownTheme: Equatable {
    var font: EditorFont = .duo
    var fontSize: CGFloat = 16
    /// Maximum line length in characters (64, 72 or 80).
    var columnCharacters = 64

    static let columnChoices = [64, 72, 80]

    var bodyFont: NSFont { font.font(size: fontSize) }
    var monoFont: NSFont { EditorFont.mono.font(size: fontSize * 0.94) }

    func headingFont(level: UInt8) -> NSFont {
        let scale: [CGFloat] = [1.25, 1.15, 1.07, 1, 1, 1]
        let index = max(0, min(Int(level) - 1, scale.count - 1))
        return font.font(size: (fontSize * scale[index]).rounded(), bold: true)
    }

    var textColor: NSColor { Palette.ink }
    /// Syntax characters: visible but quiet, like iA Writer.
    var markerColor: NSColor { Palette.ink3 }
    var secondaryColor: NSColor { Palette.ink2 }
    var linkColor: NSColor { Palette.accent }
    var mathColor: NSColor { Palette.ink2 }
    var codeBackground: NSColor { Palette.code }
    /// iA's blue caret.
    static let caretColor = Palette.accent

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = 1.45
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: bodyFont, .foregroundColor: textColor, .paragraphStyle: paragraphStyle]
    }

    /// Width of the text column.
    var columnWidth: CGFloat {
        let sample = String(repeating: "0", count: columnCharacters) as NSString
        return ceil(sample.size(withAttributes: [.font: bodyFont]).width)
    }

    /// Attributes that make source characters (nearly) invisible and zero-width.
    static var hiddenAttributes: [NSAttributedString.Key: Any] { [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ] }

    static let standard = MarkdownTheme()

    /// From user settings.
    static func current(_ defaults: UserDefaults = .standard) -> MarkdownTheme {
        MarkdownTheme(
            font: defaults.string(forKey: EditorSettings.fontKey).flatMap(EditorFont.init) ?? .duo,
            fontSize: CGFloat(defaults.object(forKey: EditorSettings.fontSizeKey) as? Double ?? 16),
            columnCharacters: defaults.object(forKey: EditorSettings.columnKey) as? Int ?? 64
        )
    }
}

/// UserDefaults keys for editor preferences.
enum EditorSettings {
    static let fontKey = "editorFont"
    static let fontSizeKey = "editorFontSize"
    static let typewriterKey = "typewriterMode"
    static let focusKey = "focusMode"
    static let columnKey = "columnCharacters"
    static let fontSizes: ClosedRange<Double> = 12...26
}
