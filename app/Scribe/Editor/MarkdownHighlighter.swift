import AppKit
import MdCore

/// Styles Markdown source in an `NSTextStorage` from spans parsed by the Rust core.
/// Markers stay visible (dimmed); hiding them is M3.
@MainActor
final class MarkdownHighlighter {
    var theme: MarkdownTheme
    private(set) var spans: [MarkdownSpan] = []

    init(theme: MarkdownTheme = .standard) {
        self.theme = theme
    }

    /// Restyles everything (new document, theme change).
    func highlightAll(_ storage: NSTextStorage) {
        spans = parseMarkdown(text: storage.string)
        restyle(storage, in: NSRange(location: 0, length: storage.length))
    }

    /// Restyles only what an edit can have affected. Call from
    /// `textStorage(_:didProcessEditing:range:changeInLength:)`.
    func textDidChange(_ storage: NSTextStorage, editedRange: NSRange, changeInLength delta: Int) {
        let new = parseMarkdown(text: storage.string)
        var dirty = SpanDiff.dirtyRange(old: spans, new: new, edited: editedRange, delta: delta)
        spans = new
        dirty = NSIntersectionRange(dirty, NSRange(location: 0, length: storage.length))
        restyle(storage, in: (storage.string as NSString).paragraphRange(for: dirty))
    }

    private func restyle(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 || storage.length == 0 else { return }
        storage.beginEditing()
        storage.setAttributes(theme.baseAttributes, range: range)
        let relevant = spans.filter { NSIntersectionRange($0.range.nsRange, range).length > 0 }
        // Element styles first (parents before children, so traits accumulate)…
        for span in relevant {
            apply(span, to: storage, clippedTo: range)
        }
        // …then markers on top, so syntax is always dimmed.
        for span in relevant {
            for marker in span.markers {
                let r = NSIntersectionRange(marker.nsRange, range)
                if r.length > 0 { storage.addAttribute(.foregroundColor, value: theme.markerColor, range: r) }
            }
        }
        storage.endEditing()
    }

    private func apply(_ span: MarkdownSpan, to storage: NSTextStorage, clippedTo clip: NSRange) {
        let r = NSIntersectionRange(span.range.nsRange, clip)
        guard r.length > 0 else { return }
        switch span.kind {
        case .heading(let level):
            storage.addAttribute(.font, value: theme.headingFont(level: level), range: r)
        case .emphasis:
            addTrait(.italicFontMask, to: storage, in: r)
        case .strong:
            addTrait(.boldFontMask, to: storage, in: r)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            storage.addAttribute(.foregroundColor, value: theme.secondaryColor, range: r)
        case .code, .codeBlock:
            storage.addAttributes([.font: theme.monoFont, .backgroundColor: theme.codeBackground], range: r)
        case .math, .mathBlock:
            storage.addAttributes([.font: theme.monoFont, .foregroundColor: theme.mathColor], range: r)
        case .table:
            storage.addAttribute(.font, value: theme.monoFont, range: r)
        case .blockQuote, .html, .image:
            storage.addAttribute(.foregroundColor, value: theme.secondaryColor, range: r)
        case .link, .footnoteReference:
            storage.addAttribute(.foregroundColor, value: theme.linkColor, range: r)
        case .listItem, .taskMarker, .thematicBreak, .footnoteDefinition:
            break // markers only
        }
    }

    private func addTrait(_ trait: NSFontTraitMask, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? theme.bodyFont
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: subrange)
        }
    }
}
