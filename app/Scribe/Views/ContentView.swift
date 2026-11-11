import SwiftUI

/// The window: one sheet of paper. The library, Quick Open, status and conflict
/// toasts float above the text and only appear when needed.
struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0
    @AppStorage(EditorSettings.columnKey) private var columnCharacters = 64
    @AppStorage(EditorSettings.typewriterKey) private var typewriterMode = false
    @AppStorage(EditorSettings.focusKey) private var focusMode = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.paper.ignoresSafeArea()
            detail
                .padding(.leading, library.isSidebarVisible ? Metrics.sidebarWidth + Metrics.panelInset : 0)
                .ignoresSafeArea()
            windowTitle
            if library.isSidebarVisible {
                LibraryPanel()
                    .frame(width: Metrics.sidebarWidth)
                    .padding(Metrics.panelInset)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
            if let document = library.document {
                StatusBar(document: document, focusMode: focusMode, typewriterMode: typewriterMode)
                if let conflict = document.conflict {
                    ConflictToast(conflict: conflict, document: document) { library.selection = nil }
                }
            }
            if library.isQuickOpenPresented {
                QuickOpenView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : Metrics.panelAnimation, value: library.isSidebarVisible)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: library.isQuickOpenPresented)
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { library.errorMessage != nil }, set: { if !$0 { library.errorMessage = nil } }),
            presenting: library.errorMessage
        ) { _ in
            Button("OK") {}
        } message: { Text($0) }
    }

    @ViewBuilder private var detail: some View {
        if library.root == nil {
            EmptyStateView(
                title: "Choose a folder for your notes.",
                hints: [("⌘O", "Open Library")],
                action: { library.chooseLibrary() }
            )
        } else if let document = library.document {
            EditorView(
                document: document,
                reloadGeneration: document.reloadGeneration,
                reveal: library.pendingReveal.flatMap { library.url(for: $0.relativePath) == document.url ? $0 : nil },
                onRevealed: { library.revealHandled($0) },
                libraryRoot: library.root,
                theme: MarkdownTheme(font: font, fontSize: CGFloat(fontSize), columnCharacters: columnCharacters),
                typewriterMode: typewriterMode,
                focusMode: focusMode
            )
        } else {
            EmptyStateView(
                title: "Start writing.",
                hints: [("⌘N", "New Note"), ("⌘P", "Open"), ("⌘⇧L", "Library")],
                action: { library.newNote() }
            )
        }
    }

    /// The note's name, quiet and centered in the (hidden) title bar.
    private var windowTitle: some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.ink3)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.horizontal, 120)
            .allowsHitTesting(false)
    }

    private var title: String {
        library.document?.url.deletingPathExtension().lastPathComponent ?? ""
    }
}

/// A calm empty window: one sentence in the editor's typeface and the shortcuts.
struct EmptyStateView: View {
    let title: String
    let hints: [(key: String, label: String)]
    let action: () -> Void
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo

    var body: some View {
        VStack(spacing: 12) {
            Button(action: action) {
                Text(title)
                    .font(Font(font.font(size: 18)))
                    .foregroundStyle(Color.ink3)
            }
            .buttonStyle(.plain)
            HStack(spacing: 14) {
                ForEach(hints, id: \.key) { hint in
                    HStack(spacing: 4) {
                        Text(hint.key).fontWeight(.semibold)
                        Text(hint.label)
                    }
                }
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Color.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
