import SwiftUI

struct ContentView: View {
    @Environment(LibraryModel.self) private var library
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0
    @AppStorage(EditorSettings.typewriterKey) private var typewriterMode = false
    @AppStorage(EditorSettings.focusKey) private var focusMode = false

    var body: some View {
        @Bindable var library = library
        @Bindable var search = library.search
        NavigationSplitView(columnVisibility: $library.columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
        } detail: {
            detail
        }
        .navigationTitle(title)
        .searchable(text: $search.query, isPresented: $library.isSearchPresented,
                    placement: .sidebar, prompt: "Search Library")
        .sheet(isPresented: $library.isQuickOpenPresented) {
            QuickOpenView()
        }
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
            ContentUnavailableView {
                Label("No Library", systemImage: "folder")
            } description: {
                Text("Choose a folder with your Markdown notes.")
            } actions: {
                Button("Open Library…") { library.chooseLibrary() }
                    .keyboardShortcut(.defaultAction)
            }
        } else if let document = library.document {
            VStack(spacing: 0) {
                if let conflict = document.conflict {
                    ConflictBanner(conflict: conflict, document: document) { library.selection = nil }
                }
                EditorView(
                    document: document,
                    reloadGeneration: document.reloadGeneration,
                    reveal: library.pendingReveal.flatMap { library.url(for: $0.relativePath) == document.url ? $0 : nil },
                    onRevealed: { library.revealHandled($0) },
                    libraryRoot: library.root,
                    theme: MarkdownTheme(font: font, fontSize: CGFloat(fontSize)),
                    typewriterMode: typewriterMode,
                    focusMode: focusMode
                )
            }
        } else {
            ContentUnavailableView {
                Label("No Note Selected", systemImage: "doc.text")
            } description: {
                Text("Select a note in the sidebar or create a new one.")
            } actions: {
                Button("New Note") { library.newNote() }
            }
        }
    }

    private var title: String {
        if let document = library.document {
            return document.url.deletingPathExtension().lastPathComponent
        }
        return library.root?.lastPathComponent ?? "Scribe"
    }
}

private struct ConflictBanner: View {
    let conflict: NoteDocument.Conflict
    let document: NoteDocument
    let close: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            switch conflict {
            case .modifiedOnDisk:
                Text("This note changed on disk.")
                Spacer()
                Button("Reload") { document.reloadFromDisk() }
                Button("Keep Mine") { document.keepMine() }
            case .deletedOnDisk:
                Text("This note was deleted on disk.")
                Spacer()
                Button("Close") { close() }
                Button("Keep Mine") { document.keepMine() }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}
