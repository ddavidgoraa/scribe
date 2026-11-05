import AppKit
import SwiftUI

/// Plain-text Markdown editor backed by NSTextView (TextKit 2).
/// Styling and marker hiding arrive in M2/M3.
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
        textView.font = .systemFont(ofSize: 16)
        textView.textContainerInset = NSSize(width: 40, height: 32)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = document.text
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        context.coordinator.textView = textView
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
            textView.string = document.text
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.undoManager?.removeAllActions()
            textView.scrollToBeginningOfDocument(nil)
        } else if coordinator.reloadGeneration != document.reloadGeneration {
            // Reloaded from disk: keep the caret where it was (clamped).
            coordinator.reloadGeneration = document.reloadGeneration
            let selection = textView.selectedRange()
            textView.string = document.text
            let length = (document.text as NSString).length
            let location = min(selection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(selection.length, length - location)))
            textView.undoManager?.removeAllActions()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: NoteDocument
        weak var textView: NSTextView?
        var reloadGeneration = 0

        init(document: NoteDocument) { self.document = document }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            document.text = textView.string
        }
    }
}
