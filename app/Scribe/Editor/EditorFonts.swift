import AppKit

/// The editor's typefaces: Apple's system families, so nothing is bundled and text
/// renders exactly as macOS intends.
enum EditorFont: String, CaseIterable, Identifiable {
    /// SF Pro.
    case sans
    /// New York.
    case serif
    /// SF Mono.
    case mono

    static let `default`: EditorFont = .sans

    var id: Self { self }
    var title: String {
        switch self {
        case .sans: "Sans"
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }

    /// The system font in this design; values saved by older versions fall back to the default.
    init(storedValue: String?) {
        self = storedValue.flatMap(EditorFont.init(rawValue:)) ?? .default
    }

    func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let base: NSFont = switch self {
        case .sans: .systemFont(ofSize: size)
        case .serif: Self.serifFont(size: size)
        case .mono: .monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return EditorFonts.adding(bold: bold, italic: italic, to: base)
    }

    private static func serifFont(size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size)
        guard let descriptor = system.fontDescriptor.withDesign(.serif) else { return system }
        return NSFont(descriptor: descriptor, size: size) ?? system
    }
}

enum EditorFonts {
    /// `font` with bold and/or italic added, keeping its family and design.
    static func adding(bold: Bool = false, italic: Bool = false, to font: NSFont) -> NSFont {
        guard bold || italic else { return font }
        var traits = font.fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: font.pointSize) ?? font
    }
}
