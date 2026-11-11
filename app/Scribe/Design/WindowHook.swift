import AppKit
import SwiftUI

/// Configures the window hosting a SwiftUI view as soon as the view joins it —
/// before the window is shown, which matters for Space placement.
struct WindowHook: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.configure = configure
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.configure = configure
    }

    final class HookView: NSView {
        var configure: (NSWindow) -> Void = { _ in }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let newWindow { configure(newWindow) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension NSWindow {
    /// Secondary windows (Settings, Help) open on top of a full-screen Scribe window
    /// instead of on another desktop.
    func showsOverFullScreen() {
        collectionBehavior.insert(.fullScreenAuxiliary)
        collectionBehavior.insert(.moveToActiveSpace)
    }
}
