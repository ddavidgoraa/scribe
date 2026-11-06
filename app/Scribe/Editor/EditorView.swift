import AppKit
import SwiftUI

/// Markdown editor backed by NSTextView (TextKit 2). The text is the file verbatim;
/// `MarkdownHighlighter` only adds attributes. Marker hiding arrives in M3.
struct EditorView: NSViewRepresentable {
    @Bindable var document: NoteDocument

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.font = MarkdownTheme.standard.bodyFont
        textView.typingAttributes = MarkdownTheme.standard.baseAttributes
        textView.textContainerInset = NSSize(width: 40, height: 32)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.load(document.text)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        context.coordinator.reloadGeneration = document.reloadGeneration

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
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
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, @preconcurrency NSTextStorageDelegate {
        var document: NoteDocument
        weak var textView: NSTextView?
        var reloadGeneration = 0
        let highlighter = MarkdownHighlighter()
        /// Set while replacing the whole text, which is restyled in one pass instead.
        private var isLoading = false

        init(document: NoteDocument) { self.document = document }

        /// Replaces the whole text and restyles it.
        func load(_ text: String) {
            guard let textView, let storage = textView.textStorage else { return }
            isLoading = true
            textView.string = text
            isLoading = false
            highlighter.highlightAll(storage)
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
