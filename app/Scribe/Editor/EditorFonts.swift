import AppKit
import CoreText

/// The bundled iA Writer typefaces (SIL OFL 1.1, see Resources/Fonts/LICENSE-*).
enum EditorFont: String, CaseIterable, Identifiable {
    case duo, mono, quattro

    var id: Self { self }
    var title: String {
        switch self {
        case .duo: "iA Writer Duo"
        case .mono: "iA Writer Mono"
        case .quattro: "iA Writer Quattro"
        }
    }

    /// PostScript name prefix of the static fonts, e.g. `iAWriterDuoS-Bold`.
    fileprivate var postScriptPrefix: String {
        switch self {
        case .duo: "iAWriterDuoS"
        case .mono: "iAWriterMonoS"
        case .quattro: "iAWriterQuattroS"
        }
    }

    func font(size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        EditorFonts.registerBundledFonts()
        let style = switch (bold, italic) {
        case (false, false): "Regular"
        case (true, false): "Bold"
        case (false, true): "Italic"
        case (true, true): "BoldItalic"
        }
        return NSFont(name: "\(postScriptPrefix)-\(style)", size: size)
            ?? (bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size))
    }
}

enum EditorFonts {
    /// `font` with bold/italic added, keeping its iA family (by PostScript name).
    static func adding(bold: Bool = false, italic: Bool = false, to font: NSFont) -> NSFont {
        let name = font.fontName
        if name.hasPrefix("iAWriter"), let dash = name.firstIndex(of: "-") {
            let prefix = name[..<dash]
            let style = name[name.index(after: dash)...]
            let isBold = bold || style.contains("Bold")
            let isItalic = italic || style.contains("Italic")
            let newStyle = isBold && isItalic ? "BoldItalic" : isBold ? "Bold" : isItalic ? "Italic" : "Regular"
            if let converted = NSFont(name: "\(prefix)-\(newStyle)", size: font.pointSize) { return converted }
        }
        var result = font
        if bold { result = NSFontManager.shared.convert(result, toHaveTrait: .boldFontMask) }
        if italic { result = NSFontManager.shared.convert(result, toHaveTrait: .italicFontMask) }
        return result
    }

    /// Registers the app's bundled fonts for this process (idempotent).
    static func registerBundledFonts() {
        _ = registration
    }

    private static let registration: Void = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
