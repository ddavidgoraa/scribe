import AppKit
import MdCore

/// Styles Markdown source in an `NSTextStorage` from spans parsed by the Rust core.
///
/// Live preview: elements the caret does not touch hide their markers; math and images
/// are drawn by `DecoratedLayoutFragment` over their hidden source. The text itself is
/// never changed, only attributes.
@MainActor
final class MarkdownHighlighter {
    var theme: MarkdownTheme
    /// Folder of the note, for relative image paths.
    var baseURL: URL?
    /// Largest size of an image preview.
    var maxImageSize = CGSize(width: 560, height: 360)
    /// Printing: syntax the editor keeps visible (list bullets, task boxes, rules) is
    /// replaced by its typeset form too, for a clean page.
    var printMode = false
    private(set) var spans: [MarkdownSpan] = []
    /// Caret position, or `nil` while a range is selected.
    private(set) var caret: Int?

    init(theme: MarkdownTheme = .standard) {
        self.theme = theme
    }

    // MARK: Updates

    /// Restyles everything (new document, theme change).
    func highlightAll(_ storage: NSTextStorage) {
        spans = parseMarkdown(text: storage.string)
        restyle(storage, in: NSRange(location: 0, length: storage.length))
    }

    /// Restyles what an edit can have affected. Call from
    /// `textStorage(_:didProcessEditing:range:changeInLength:)`.
    func textDidChange(_ storage: NSTextStorage, editedRange: NSRange, changeInLength delta: Int) {
        let new = parseMarkdown(text: storage.string)
        var dirty = SpanDiff.dirtyRange(old: spans, new: new, edited: editedRange, delta: delta)
        // The caret is right after the edit while typing; the selection update follows.
        let oldCaret = caret.map { $0 >= editedRange.location ? max(0, $0 + delta) : $0 }
        caret = NSMaxRange(editedRange)
        for span in new where Presentation.isActive(span, caret: oldCaret) != Presentation.isActive(span, caret: caret) {
            dirty = NSUnionRange(dirty, span.range.nsRange)
        }
        spans = new
        dirty = NSIntersectionRange(dirty, NSRange(location: 0, length: storage.length))
        restyle(storage, in: (storage.string as NSString).paragraphRange(for: dirty))
    }

    /// Reveals/hides markers for a new selection. A range selection keeps the current
    /// state, so dragging across elements doesn't make the text jump.
    func selectionDidChange(_ storage: NSTextStorage, selection: NSRange) {
        guard selection.length == 0 else { return }
        let new = selection.location
        guard new != caret else { return }
        let old = caret
        caret = new
        var dirty: NSRange?
        for span in spans where Presentation.isActive(span, caret: old) != Presentation.isActive(span, caret: new) {
            dirty = dirty.map { NSUnionRange($0, span.range.nsRange) } ?? span.range.nsRange
        }
        guard var dirty else { return }
        dirty = NSIntersectionRange(dirty, NSRange(location: 0, length: storage.length))
        restyle(storage, in: (storage.string as NSString).paragraphRange(for: dirty))
    }

    /// Sets the caret without restyling (before the first `highlightAll`).
    func resetCaret(_ caret: Int?) {
        self.caret = caret
    }

    // MARK: Styling

    private func restyle(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 || storage.length == 0 else { return }
        let text = storage.string as NSString
        storage.beginEditing()
        storage.setAttributes(theme.baseAttributes, range: range)
        let relevant = spans.filter { NSIntersectionRange($0.range.nsRange, range).length > 0 }
        // Element styles first (parents before children, so traits accumulate)…
        for span in relevant {
            apply(span, to: storage, clippedTo: range)
        }
        // …then markers on top, so syntax is always dimmed…
        for span in relevant {
            for marker in span.markers {
                let r = NSIntersectionRange(marker.nsRange, range)
                if r.length > 0 { storage.addAttribute(.foregroundColor, value: theme.markerColor, range: r) }
            }
        }
        // …then live preview: hide and decorate inactive elements.
        for span in relevant where Presentation.hidesMarkers(span.kind) || (printMode && Presentation.typesetForPrint(span.kind)) {
            present(span, active: Presentation.isActive(span, caret: caret), in: storage, text: text, clip: range)
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
            addTrait(italic: true, to: storage, in: r)
        case .strong:
            addTrait(bold: true, to: storage, in: r)
        case .strikethrough:
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: r)
            storage.addAttribute(.foregroundColor, value: theme.secondaryColor, range: r)
        case .code:
            storage.addAttributes([.font: theme.monoFont, .backgroundColor: theme.codeBackground], range: r)
        case .codeBlock:
            storage.addAttributes([.font: theme.monoFont, .scribeBlockBackground: theme.codeBackground], range: r)
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

    // MARK: Live preview

    private func present(_ span: MarkdownSpan, active: Bool, in storage: NSTextStorage, text: NSString, clip: NSRange) {
        let range = span.range.nsRange
        switch span.kind {
        case .math, .mathBlock:
            presentMath(span, active: active, in: storage, text: text, clip: clip)
        case .image:
            guard !active else { return }
            if Presentation.isStandalone(range, in: text),
               let url = Presentation.imageURL(of: span, in: text, base: baseURL),
               let image = ImageCache.shared.image(at: url) {
                let size = fit(image.size, in: maxImageSize)
                presentBlock(Decoration(image: image, size: size, placement: .block), source: range, in: storage, text: text, clip: clip)
            } else {
                hideMarkers(of: span, in: storage, clip: clip)
            }
        case .codeBlock:
            // Fenced only (indented blocks have no markers); keep empty blocks visible.
            guard !active, span.markers.count == 2 else { return }
            for marker in span.markers {
                hide(withTrailingNewline(marker.nsRange, in: text), in: storage, clip: clip)
            }
        case .blockQuote:
            guard !active else { return }
            hideMarkers(of: span, in: storage, clip: clip)
            indent(range, by: 18, in: storage, clip: clip)
        case .listItem:
            presentListMarker(span, in: storage, text: text, clip: clip)
        case .taskMarker(let checked):
            let decoration = PrintGlyphs.checkbox(checked: checked, font: theme.bodyFont)
            presentInline(decoration, over: range, in: storage, clip: clip)
        case .thematicBreak:
            let decoration = PrintGlyphs.rule(width: maxImageSize.width)
            presentBlock(decoration, source: range, in: storage, text: text, clip: clip)
        default:
            guard !active else { return }
            hideMarkers(of: span, in: storage, clip: clip)
        }
    }

    /// Print: `- ` becomes a bullet; a task item's `- ` disappears (its box is drawn by
    /// the task marker); `1. ` stays, in the text color.
    private func presentListMarker(_ span: MarkdownSpan, in storage: NSTextStorage, text: NSString, clip: NSRange) {
        guard let marker = span.markers.first?.nsRange else { return }
        let symbol = text.substring(with: marker).trimmingCharacters(in: .whitespaces)
        guard ["-", "*", "+"].contains(symbol) else {
            let r = NSIntersectionRange(marker, clip)
            if r.length > 0 { storage.addAttribute(.foregroundColor, value: theme.textColor, range: r) }
            return
        }
        let after = NSMaxRange(marker)
        let rest = text.substring(with: NSRange(location: after, length: min(3, text.length - after)))
        if ["[ ]", "[x]", "[X]"].contains(rest) {
            hide(marker, in: storage, clip: clip)
        } else {
            presentInline(PrintGlyphs.bullet(font: theme.bodyFont), over: marker, in: storage, clip: clip)
        }
    }

    /// Hides `range` and draws `decoration` in its place, reserving its width.
    private func presentInline(_ decoration: Decoration, over range: NSRange, in storage: NSTextStorage, clip: NSRange) {
        hide(range, in: storage, clip: clip)
        guard NSLocationInRange(range.location, clip) else { return }
        storage.addAttributes([.scribeDecoration: decoration, .kern: decoration.size.width],
                              range: NSRange(location: range.location, length: 1))
    }

    private func presentMath(_ span: MarkdownSpan, active: Bool, in storage: NSTextStorage, text: NSString, clip: NSRange) {
        let range = span.range.nsRange
        let block = span.kind == .mathBlock && Presentation.isStandalone(range, in: text)
        let latex = Presentation.content(of: span, in: text)
        let fontSize = block ? theme.fontSize * 1.15 : theme.fontSize
        switch MathRenderer.shared.render(latex, display: span.kind == .mathBlock, fontSize: fontSize) {
        case .failure(let failure):
            // Show the source in red with the error as a tooltip, even when inactive.
            let r = NSIntersectionRange(range, clip)
            guard r.length > 0 else { return }
            storage.addAttribute(.toolTip, value: failure.message, range: r)
            for content in contentRanges(of: span) {
                let c = NSIntersectionRange(content, clip)
                if c.length > 0 { storage.addAttribute(.foregroundColor, value: NSColor.systemRed, range: c) }
            }
        case .success(let rendered):
            if active {
                if block { presentPreview(rendered, below: range, in: storage, text: text, clip: clip) }
                return
            }
            if block {
                let decoration = Decoration(image: rendered.image, size: rendered.size, placement: .block, tinted: true)
                presentBlock(decoration, source: range, in: storage, text: text, clip: clip)
            } else {
                let decoration = Decoration(image: rendered.image, size: rendered.size, ascent: rendered.ascent, placement: .inline, tinted: true)
                hide(range, in: storage, clip: clip)
                guard NSLocationInRange(range.location, clip) else { return }
                let first = NSRange(location: range.location, length: 1)
                storage.addAttributes([.scribeDecoration: decoration, .kern: rendered.size.width], range: first)
            }
        }
    }

    /// Hides `source` (whole lines) and reserves one line tall enough for the decoration.
    private func presentBlock(_ decoration: Decoration, source: NSRange, in storage: NSTextStorage, text: NSString, clip: NSRange) {
        hide(withTrailingNewline(source, in: text), in: storage, clip: clip)
        let firstLine = text.lineRange(for: NSRange(location: source.location, length: 0))
        let r = NSIntersectionRange(firstLine, clip)
        guard r.length > 0 else { return }
        let style = theme.paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
        style.lineHeightMultiple = 1
        style.minimumLineHeight = decoration.size.height + 2 * Decoration.blockPadding
        style.maximumLineHeight = style.minimumLineHeight
        storage.addAttribute(.paragraphStyle, value: style, range: r)
        if NSLocationInRange(source.location, clip) {
            storage.addAttribute(.scribeDecoration, value: decoration, range: NSRange(location: source.location, length: 1))
        }
    }

    /// Live preview of block math while editing it: drawn below the closing line.
    private func presentPreview(_ rendered: MathRenderer.Rendered, below source: NSRange, in storage: NSTextStorage, text: NSString, clip: NSRange) {
        let lastLine = text.lineRange(for: NSRange(location: max(source.location, NSMaxRange(source) - 1), length: 0))
        let r = NSIntersectionRange(lastLine, clip)
        guard r.length > 0 else { return }
        let style = (storage.attribute(.paragraphStyle, at: r.location, effectiveRange: nil) as? NSParagraphStyle ?? theme.paragraphStyle)
            .mutableCopy() as! NSMutableParagraphStyle
        style.paragraphSpacing = rendered.size.height + 2 * Decoration.blockPadding
        storage.addAttribute(.paragraphStyle, value: style, range: r)
        let decoration = Decoration(image: rendered.image, size: rendered.size, placement: .below, tinted: true)
        storage.addAttribute(.scribeDecoration, value: decoration, range: NSRange(location: lastLine.location, length: 1))
    }

    // MARK: Helpers

    private func hideMarkers(of span: MarkdownSpan, in storage: NSTextStorage, clip: NSRange) {
        for marker in span.markers { hide(marker.nsRange, in: storage, clip: clip) }
    }

    /// Collapses characters to (almost) nothing. They stay in the text and the file.
    private func hide(_ range: NSRange, in storage: NSTextStorage, clip: NSRange) {
        let r = NSIntersectionRange(range, clip)
        guard r.length > 0 else { return }
        storage.addAttributes(MarkdownTheme.hiddenAttributes, range: r)
        storage.removeAttribute(.backgroundColor, range: r)
        storage.removeAttribute(.scribeBlockBackground, range: r)
    }

    private func indent(_ range: NSRange, by amount: CGFloat, in storage: NSTextStorage, clip: NSRange) {
        let r = NSIntersectionRange(range, clip)
        guard r.length > 0 else { return }
        storage.enumerateAttribute(.paragraphStyle, in: r) { value, sub, _ in
            let style = (value as? NSParagraphStyle ?? theme.paragraphStyle).mutableCopy() as! NSMutableParagraphStyle
            style.firstLineHeadIndent = amount
            style.headIndent = amount
            storage.addAttribute(.paragraphStyle, value: style, range: sub)
        }
    }

    private func withTrailingNewline(_ range: NSRange, in text: NSString) -> NSRange {
        let end = NSMaxRange(range)
        guard end < text.length, text.character(at: end) == 0x0A else { return range }
        return NSRange(location: range.location, length: range.length + 1)
    }

    private func contentRanges(of span: MarkdownSpan) -> [NSRange] {
        let start = span.markers.first.map { Int($0.end) } ?? Int(span.range.start)
        let end = span.markers.count > 1 ? Int(span.markers.last!.start) : Int(span.range.end)
        return end > start ? [NSRange(location: start, length: end - start)] : []
    }

    private func fit(_ size: CGSize, in bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    private func addTrait(bold: Bool = false, italic: Bool = false, to storage: NSTextStorage, in range: NSRange) {
        storage.enumerateAttribute(.font, in: range) { value, subrange, _ in
            let font = value as? NSFont ?? theme.bodyFont
            storage.addAttribute(.font, value: EditorFonts.adding(bold: bold, italic: italic, to: font), range: subrange)
        }
    }
}

/// Image previews, reloaded when the file changes.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var cache: [URL: (modified: Date, image: NSImage)] = [:]

    func image(at url: URL) -> NSImage? {
        guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        else { return nil }
        if let hit = cache[url], hit.modified == modified { return hit.image }
        guard let image = NSImage(contentsOf: url), image.size.width > 0 else { return nil }
        if cache.count > 100 { cache.removeAll() }
        cache[url] = (modified, image)
        return image
    }
}
