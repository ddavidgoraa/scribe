import AppKit
import MdCore

/// The editor's text view: Markdown formatting actions, reached through the
/// responder chain from the Format menu (`NSApp.sendAction(_:to: nil, from:)`).
final class MarkdownTextView: NSTextView {
    @objc func toggleBold(_ sender: Any?) { apply(Formatting.toggleWrap("**", text: nsString, selection: selectedRange())) }
    @objc func toggleItalic(_ sender: Any?) { apply(Formatting.toggleWrap("*", text: nsString, selection: selectedRange())) }
    @objc func toggleStrikethrough(_ sender: Any?) { apply(Formatting.toggleWrap("~~", text: nsString, selection: selectedRange())) }
    @objc func toggleInlineCode(_ sender: Any?) { apply(Formatting.toggleWrap("`", text: nsString, selection: selectedRange())) }
    @objc func toggleMath(_ sender: Any?) { apply(Formatting.toggleMath(text: nsString, selection: selectedRange())) }
    @objc func insertMarkdownLink(_ sender: Any?) { apply(Formatting.insertLink(text: nsString, selection: selectedRange())) }

    /// `sender` is an `NSNumber` with the level (1–6).
    @objc func setHeadingLevel(_ sender: Any?) {
        guard let level = (sender as? NSNumber)?.intValue else { return }
        apply(Formatting.setHeading(level, text: nsString, selection: selectedRange()))
    }

    /// Copies the selection (or the whole note) as HTML: rich for apps that paste
    /// HTML, source for plain-text targets.
    @objc func copyAsHTML(_ sender: Any?) {
        let range = selectedRange()
        let markdown = range.length > 0 ? nsString.substring(with: range) : string
        let html = markdownToHtml(markdown: markdown)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        pasteboard.setString(html, forType: .string)
    }

    /// Selects `range`, scrolls to it and flashes it (search results).
    func reveal(_ range: NSRange) {
        let clamped = NSIntersectionRange(range, NSRange(location: 0, length: nsString.length))
        window?.makeFirstResponder(self)
        setSelectedRange(clamped)
        scrollRangeToVisible(clamped)
        showFindIndicator(for: clamped)
    }

    private var nsString: NSString { string as NSString }

    // MARK: Images (paste and drop)

    /// The open note's file (it can change when the note is renamed).
    var noteURL: () -> URL? = { nil }
    /// The library folder: images already inside it are linked, not copied.
    var libraryRoot: URL?

    override func paste(_ sender: Any?) {
        if insertImages(from: .general, replacing: selectedRange()) { return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + [.fileURL, .png, .tiff]
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        if noteURL() != nil, ImageInsertion.containsImages(dragInfo.draggingPasteboard) { return .copy }
        return super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard noteURL() != nil, ImageInsertion.containsImages(sender.draggingPasteboard) else {
            return super.performDragOperation(sender)
        }
        let index = characterIndexForInsertion(at: convert(sender.draggingLocation, from: nil))
        window?.makeFirstResponder(self)
        return insertImages(from: sender.draggingPasteboard, replacing: NSRange(location: index, length: 0))
    }

    /// Saves/links images from `pasteboard` and inserts their Markdown (one undoable change).
    /// Returns `false` if the pasteboard holds no images.
    @discardableResult
    func insertImages(from pasteboard: NSPasteboard, replacing range: NSRange) -> Bool {
        guard let note = noteURL(), ImageInsertion.containsImages(pasteboard) else { return false }
        do {
            let images = try ImageInsertion.images(from: pasteboard, note: note, libraryRoot: libraryRoot)
            guard !images.isEmpty else { return false }
            let markdown = ImageInsertion.markdown(images, in: nsString, replacing: range)
            let end = range.location + (markdown as NSString).length
            apply(TextEdit(range: range, replacement: markdown, selection: NSRange(location: end, length: 0)))
        } catch {
            presentError(error)
        }
        return true
    }

    // MARK: Column, typewriter and focus

    var theme: MarkdownTheme = .standard {
        didSet { if theme != oldValue { insertionPointColor = MarkdownTheme.caretColor; updateLayoutMetrics() } }
    }
    /// Keeps the caret's line vertically centered.
    var typewriterMode = false {
        didSet {
            guard typewriterMode != oldValue else { return }
            updateLayoutMetrics()
            centerCaret(animated: false)
        }
    }
    /// Dims everything but the paragraph (block between blank lines) with the caret.
    var focusMode = false {
        didSet {
            guard focusMode != oldValue else { return }
            focusedBlock = focusMode ? Self.block(around: selectedRange().location, in: nsString) : nil
            redraw(NSRange(location: 0, length: nsString.length))
        }
    }
    /// Called when the column width changes (images are fitted to it).
    var onColumnWidthChange: ((CGFloat) -> Void)?

    private(set) var focusedBlock: NSRange?
    private var columnWidth: CGFloat = 0

    func isDimmed(_ paragraph: NSRange) -> Bool {
        guard focusMode, let block = focusedBlock else { return false }
        if block.length == 0 { return paragraph.location != block.location }
        return NSIntersectionRange(paragraph, block).length == 0
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateLayoutMetrics()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        insertionPointColor = MarkdownTheme.caretColor
        updateLayoutMetrics()
    }

    /// Centers a ~64 character column; typewriter mode pads top and bottom by half
    /// a screen so the first and last lines can reach the middle.
    func updateLayoutMetrics() {
        guard let scrollView = enclosingScrollView else { return }
        let visible = scrollView.contentSize
        let horizontal = max(24, floor((visible.width - theme.columnWidth) / 2))
        let vertical = typewriterMode ? max(72, floor(visible.height / 2)) : 72
        let inset = NSSize(width: horizontal, height: vertical)
        if textContainerInset != inset { textContainerInset = inset }
        let column = max(0, visible.width - 2 * horizontal)
        if abs(column - columnWidth) >= 1 {
            columnWidth = column
            onColumnWidthChange?(column)
        }
    }

    /// Call after the selection changed (focus block, typewriter centering).
    func selectionDidChange() {
        let selection = selectedRange()
        if focusMode, selection.length == 0 {
            let block = Self.block(around: selection.location, in: nsString)
            if block != focusedBlock {
                let old = focusedBlock
                focusedBlock = block
                redraw(old.map { NSUnionRange($0, block) } ?? NSRange(location: 0, length: nsString.length))
            }
        }
        if typewriterMode, selection.length == 0 {
            DispatchQueue.main.async { [weak self] in self?.centerCaret(animated: true) }
        }
    }

    func centerCaret(animated: Bool) {
        guard typewriterMode, let window, let scrollView = enclosingScrollView,
              selectedRange().length == 0 else { return }
        let screenRect = firstRect(forCharacterRange: selectedRange(), actualRange: nil)
        guard screenRect != .zero else { return }
        let caret = convert(window.convertFromScreen(screenRect), from: nil)
        let clip = scrollView.contentView
        let maxY = max(0, frame.height - clip.bounds.height)
        let target = NSPoint(x: clip.bounds.origin.x, y: min(maxY, max(0, caret.midY - clip.bounds.height / 2)))
        guard abs(target.y - clip.bounds.origin.y) > 0.5 else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                clip.animator().setBoundsOrigin(target)
            }
        } else {
            clip.setBoundsOrigin(target)
        }
        scrollView.reflectScrolledClipView(clip)
    }

    /// Lines around `location` up to the nearest blank lines.
    static func block(around location: Int, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        let isBlank: (NSRange) -> Bool = { text.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var range = text.lineRange(for: NSRange(location: min(location, text.length), length: 0))
        if isBlank(range) { return range }
        while range.location > 0 {
            let previous = text.lineRange(for: NSRange(location: range.location - 1, length: 0))
            if isBlank(previous) { break }
            range = NSUnionRange(range, previous)
        }
        while NSMaxRange(range) < text.length {
            let next = text.lineRange(for: NSRange(location: NSMaxRange(range), length: 0))
            if isBlank(next) { break }
            range = NSUnionRange(range, next)
        }
        return range
    }

    /// Re-renders the paragraphs in `range` (focus dimming is drawn by the fragments).
    private func redraw(_ range: NSRange) {
        guard let tlm = textLayoutManager,
              let start = tlm.location(tlm.documentRange.location, offsetBy: range.location),
              let end = tlm.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { needsDisplay = true; return }
        tlm.invalidateLayout(for: textRange)
        needsDisplay = true
    }

    /// Applies an edit as one undoable change.
    private func apply(_ edit: TextEdit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }
}
