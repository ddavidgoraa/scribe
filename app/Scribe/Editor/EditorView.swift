import AppKit
import SwiftUI

/// Markdown editor backed by NSTextView (TextKit 2). The text is the file verbatim;
/// `MarkdownHighlighter` only adds attributes (styling, hidden markers, decorations).
struct EditorView: NSViewRepresentable {
    @Bindable var document: NoteDocument
    /// Passed explicitly so SwiftUI calls `updateNSView` when they change.
    var reloadGeneration: Int
    var reveal: RevealRequest?
    var onRevealed: (RevealRequest) -> Void = { _ in }
    var libraryRoot: URL?
    var theme: MarkdownTheme = .current()
    var typewriterMode = false
    var focusMode = false

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        context.coordinator.highlighter.theme = theme
        textView.theme = theme
        textView.font = theme.bodyFont
        textView.typingAttributes = theme.baseAttributes
        textView.insertionPointColor = MarkdownTheme.caretColor
        textView.drawsBackground = false
        textView.selectedTextAttributes = [.backgroundColor: Palette.selection]
        textView.textContainerInset = NSSize(width: 40, height: 32)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.textLayoutManager?.delegate = context.coordinator
        context.coordinator.textView = textView
        textView.noteURL = { [weak coordinator = context.coordinator] in coordinator?.document.url }
        textView.libraryRoot = libraryRoot
        textView.onColumnWidthChange = { [weak coordinator = context.coordinator] width in
            coordinator?.columnWidthChanged(width)
        }
        context.coordinator.load(document.text)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        context.coordinator.reloadGeneration = document.reloadGeneration
        textView.typewriterMode = typewriterMode
        textView.focusMode = focusMode

        let reveal = reveal
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            if let reveal { context.coordinator.handle(reveal, onRevealed: onRevealed) }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let textView = coordinator.textView else { return }

        if coordinator.document !== document {
            // A different note is shown in the same view.
            coordinator.document = document
            coordinator.reloadGeneration = document.reloadGeneration
            coordinator.load(document.text)
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.undoManager?.removeAllActions()
            textView.scrollToBeginningOfDocument(nil)
        } else if coordinator.reloadGeneration != document.reloadGeneration {
            // Reloaded from disk: keep the caret where it was (clamped).
            coordinator.reloadGeneration = document.reloadGeneration
            let selection = textView.selectedRange()
            coordinator.load(document.text)
            let length = (document.text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            textView.undoManager?.removeAllActions()
        }
        if let reveal {
            coordinator.handle(reveal, onRevealed: onRevealed)
        }
        if let textView = textView as? MarkdownTextView {
            if textView.theme != theme {
                coordinator.highlighter.theme = theme
                textView.theme = theme
                textView.typingAttributes = theme.baseAttributes
                if let storage = textView.textStorage { coordinator.highlighter.highlightAll(storage) }
            }
            textView.typewriterMode = typewriterMode
            textView.focusMode = focusMode
            textView.libraryRoot = libraryRoot
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate,
        @preconcurrency NSTextLayoutManagerDelegate {
        var document: NoteDocument
        weak var textView: NSTextView?
        var reloadGeneration = 0
        private var handledReveal: UUID?
        let highlighter = MarkdownHighlighter()

        func handle(_ request: RevealRequest, onRevealed: @escaping (RevealRequest) -> Void) {
            guard request.id != handledReveal, let textView = textView as? MarkdownTextView else { return }
            handledReveal = request.id
            // After SwiftUI's update pass, once the text is in place.
            DispatchQueue.main.async {
                textView.reveal(request.range)
                onRevealed(request)
            }
        }
        /// Set while replacing the whole text, which is restyled in one pass instead.
        private var isLoading = false

        init(document: NoteDocument) { self.document = document }

        /// Replaces the whole text and restyles it.
        func load(_ text: String) {
            guard let textView, let storage = textView.textStorage else { return }
            highlighter.baseURL = document.url.deletingLastPathComponent()
            isLoading = true
            textView.string = text
            isLoading = false
            highlighter.resetCaret(textView.selectedRange().length == 0 ? textView.selectedRange().location : nil)
            highlighter.highlightAll(storage)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isLoading, let textView, let storage = textView.textStorage else { return }
            highlighter.selectionDidChange(storage, selection: textView.selectedRange())
            (textView as? MarkdownTextView)?.selectionDidChange()
        }

        /// Images are fitted to the text column.
        func columnWidthChanged(_ width: CGFloat) {
            let size = CGSize(width: max(200, width), height: 420)
            guard size != highlighter.maxImageSize else { return }
            highlighter.maxImageSize = size
            if let storage = textView?.textStorage, storage.length > 0 { highlighter.highlightAll(storage) }
        }

        /// Never type with the attributes of hidden markers (invisible, 0.01 pt).
        func textView(
            _ textView: NSTextView,
            shouldChangeTypingAttributes oldTypingAttributes: [String: Any] = [:],
            toAttributes newTypingAttributes: [NSAttributedString.Key: Any] = [:]
        ) -> [NSAttributedString.Key: Any] {
            if let font = newTypingAttributes[.font] as? NSFont, font.pointSize < 1 {
                return highlighter.theme.baseAttributes
            }
            return newTypingAttributes.filter { $0.key != .scribeDecoration && $0.key != .kern }
        }

        func textLayoutManager(
            _ textLayoutManager: NSTextLayoutManager,
            textLayoutFragmentFor location: any NSTextLocation,
            in textElement: NSTextElement
        ) -> NSTextLayoutFragment {
            DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
        }

        func textStorage(
            _ textStorage: NSTextStorage,
            didProcessEditing editedMask: NSTextStorageEditActions,
            range editedRange: NSRange,
            changeInLength delta: Int
        ) {
            guard editedMask.contains(.editedCharacters), !isLoading else { return }
            highlighter.textDidChange(textStorage, editedRange: editedRange, changeInLength: delta)
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            document.text = textView.string
        }
    }
}
