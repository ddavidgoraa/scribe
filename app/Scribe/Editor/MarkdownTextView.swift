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

    /// Applies an edit as one undoable change.
    private func apply(_ edit: TextEdit) {
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selection)
    }
}
