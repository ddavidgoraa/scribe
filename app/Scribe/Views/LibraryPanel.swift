import SwiftUI

/// The floating library (⌘⇧L): search, recent notes, the folder tree. No icons:
/// hierarchy comes from indentation and weight, dates sit quietly on the right.
struct LibraryPanel: View {
    @Environment(LibraryModel.self) private var library
    @Environment(HelpModel.self) private var help
    @Environment(\.openWindow) private var openWindow
    @FocusState private var searchFocused: Bool
    @State private var renaming: LibraryNode?
    @State private var newName = ""

    var body: some View {
        @Bindable var search = library.search
        VStack(alignment: .leading, spacing: 0) {
            searchField(text: $search.query)
                .padding(.top, 40) // room for the window's traffic lights
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if library.search.isActive {
                        SearchResultsView()
                    } else {
                        tree
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .floatingPanel()
        .onChange(of: library.searchFocusRequest) { searchFocused = true }
        .onAppear { if library.searchFocusRequest > 0 { searchFocused = true } }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") { if let node = renaming { library.rename(node.id, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Search field

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11, weight: .semibold))
            TextField("Search", text: text)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onKeyPress(.escape) {
                    text.wrappedValue = ""
                    searchFocused = false
                    return .handled
                }
            if text.wrappedValue.isEmpty {
                Text("⌘⇧F").font(.system(size: 11, weight: .medium))
            } else {
                Button { text.wrappedValue = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Color.ink3)
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(Color.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: Tree

    @ViewBuilder private var tree: some View {
        let recent = library.recentNotes()
        if !recent.isEmpty {
            Text("Recent").sectionHeader().padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 6)
            ForEach(recent) { node in noteRow(node, depth: 0) }
            Text("Library").sectionHeader().padding(.horizontal, 8).padding(.top, 16).padding(.bottom, 6)
        }
        ForEach(library.nodes) { node in nodeRows(node, depth: 0) }
    }

    private func nodeRows(_ node: LibraryNode, depth: Int) -> AnyView {
        if let children = node.children {
            let expanded = library.expandedFolders.contains(node.id)
            return AnyView(VStack(alignment: .leading, spacing: 1) {
                folderRow(node, depth: depth, expanded: expanded)
                if expanded {
                    ForEach(children) { child in nodeRows(child, depth: depth + 1) }
                }
            })
        }
        return AnyView(noteRow(node, depth: depth))
    }

    private func folderRow(_ node: LibraryNode, depth: Int, expanded: Bool) -> some View {
        Button {
            if expanded { library.expandedFolders.remove(node.id) } else { library.expandedFolders.insert(node.id) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.ink3)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 10)
                Text(node.displayName).foregroundStyle(Color.ink2)
                Spacer(minLength: 0)
            }
            .rowStyle(depth: depth, selected: false)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("New Note") { library.newNote(in: node.id) }
            Button("Show in Finder") { library.revealInFinder(node.id) }
        }
    }

    private func noteRow(_ node: LibraryNode, depth: Int) -> some View {
        let selected = library.selection == node.id
        return Button {
            library.open(node.id)
        } label: {
            HStack(spacing: 8) {
                Text(node.displayName)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.accentText : Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(ShortDate.string(for: node.modified))
                    .font(.system(size: 11.5))
                    .foregroundStyle(selected ? Color.accentText.opacity(0.7) : Color.ink3)
            }
            .rowStyle(depth: depth, selected: selected)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename…") {
                newName = node.displayName
                renaming = node
            }
            Button("Show in Finder") { library.revealInFinder(node.id) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(footerText).lineLimit(1).truncationMode(.middle)
            Spacer()
            Button {
                help.document = .gettingStarted
                openWindow(id: HelpCommands.windowID)
            } label: { Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain)
                .help("Getting Started (⌘?)")
            Button { library.newNote() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)) }
                .buttonStyle(.plain)
                .help("New Note (⌘N)")
        }
        .font(.system(size: 12))
        .foregroundStyle(Color.ink3)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contextMenu { Button("Open Library…") { library.chooseLibrary() } }
    }

    private var footerText: String {
        guard let root = library.root else { return "" }
        let path = (root.path as NSString).abbreviatingWithTildeInPath
        let count = library.noteCount
        return "\(path) · \(count) \(count == 1 ? "note" : "notes")"
    }
}

private extension View {
    func rowStyle(depth: Int, selected: Bool) -> some View {
        self
            .font(.system(size: 13.5))
            .padding(.leading, CGFloat(depth) * 16)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(selected ? Color.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
    }
}
