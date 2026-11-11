import MdCore
import SwiftUI

/// Bottom-right pills: words and reading time, save state, active modes.
/// Shown while the pointer moves over the window, hidden while typing.
struct StatusBar: View {
    let document: NoteDocument
    let focusMode: Bool
    let typewriterMode: Bool
    @State private var visible = false
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let stats = textStats(text: document.text)
        HStack(spacing: 8) {
            if focusMode { pill("Focus", accent: true) }
            if typewriterMode { pill("Typewriter", accent: true) }
            pill(document.isDirty ? "Edited" : "Saved")
            pill(wordsLabel(stats))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .opacity(visible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: visible)
        .allowsHitTesting(false)
        .background(
            // Tracks the pointer over the whole window without blocking clicks.
            HoverTracker { show() }
        )
        .onChange(of: document.text) { hide() }
    }

    private func wordsLabel(_ stats: TextStats) -> String {
        let words = stats.words == 1 ? "1 word" : "\(stats.words.formatted()) words"
        return stats.readingMinutes > 0 ? "\(words) · \(stats.readingMinutes) min read" : words
    }

    private func pill(_ text: String, accent: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(accent ? Color.accentText : Color.ink3)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.paper.opacity(0.85), in: Capsule())
            .overlay(Capsule().strokeBorder(accent ? Color.accentBlue.opacity(0.35) : Color.line))
    }

    private func show() {
        visible = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            visible = false
        }
    }

    private func hide() {
        hideTask?.cancel()
        visible = false
    }
}

/// Reports pointer movement anywhere in the window (without intercepting events).
private struct HoverTracker: NSViewRepresentable {
    let onMove: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: TrackingView, context: Context) {
        view.onMove = onMove
    }

    final class TrackingView: NSView {
        var onMove: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                if event.window === self?.window { self?.onMove() }
                return event
            }
            window?.acceptsMouseMovedEvents = true
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Floating toast for a note changed or deleted on disk while edited here.
struct ConflictToast: View {
    let conflict: NoteDocument.Conflict
    let document: NoteDocument
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            switch conflict {
            case .modifiedOnDisk:
                Text("This note changed on disk")
                button("Reload", primary: false) { document.reloadFromDisk() }
                button("Keep Mine", primary: true) { document.keepMine() }
            case .deletedOnDisk:
                Text("This note was deleted on disk")
                button("Close", primary: false) { close() }
                button("Keep Mine", primary: true) { document.keepMine() }
            }
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.leading, 18)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.toast, in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func button(_ title: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(primary ? Color.accentBlue : Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
