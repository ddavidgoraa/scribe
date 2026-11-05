import SwiftUI

struct SidebarView: View {
    @Environment(LibraryModel.self) private var library
    @State private var renaming: LibraryNode?
    @State private var newName = ""

    var body: some View {
        @Bindable var library = library
        List(selection: $library.selection) {
            OutlineGroup(library.nodes, children: \.children) { node in
                Label(node.displayName, systemImage: node.isDir ? "folder" : "doc.text")
                    .tag(node.id)
                    .contextMenu { menu(for: node) }
            }
        }
        .contextMenu {
            if library.root != nil {
                Button("New Note") { library.newNote(in: "") }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { library.newNote() } label: { Label("New Note", systemImage: "square.and.pencil") }
                    .disabled(library.root == nil)
            }
        }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let node = renaming { library.rename(node.id, to: newName) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder private func menu(for node: LibraryNode) -> some View {
        if node.isDir {
            Button("New Note") { library.newNote(in: node.id) }
        } else {
            Button("Rename…") {
                newName = node.displayName
                renaming = node
            }
        }
        Button("Show in Finder") { library.revealInFinder(node.id) }
    }
}
