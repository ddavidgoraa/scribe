import MdCore
import SwiftUI

/// ⌘P: a Spotlight-like palette. Fuzzy-find a note by name or path; ⌘⏎ creates a
/// note titled with what you typed.
struct QuickOpenView: View {
    @Environment(LibraryModel.self) private var library
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private struct Row: Identifiable {
        let id: String
        let name: AttributedString
        let folder: String
    }

    var body: some View {
        let paths = library.notePaths
        let rows = Self.rows(paths: paths, query: query)
        ZStack(alignment: .top) {
            // Click outside to dismiss.
            Color.black.opacity(0.001).onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.ink3)
                    TextField("Open or create a note", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22))
                        .foregroundStyle(Color.ink)
                        .focused($focused)
                        .onKeyPress(.downArrow) { move(1, count: rows.count); return .handled }
                        .onKeyPress(.upArrow) { move(-1, count: rows.count); return .handled }
                        .onKeyPress(.escape) { close(); return .handled }
                        .onKeyPress(keys: [.return]) { press in
                            if press.modifiers.contains(.command) { create() } else { open(rows) }
                            return .handled
                        }
                        .onChange(of: query) { selected = 0 }
                }
                .padding(.horizontal, 22)
                .frame(height: 62)
                if !rows.isEmpty {
                    Divider().overlay(Color.line)
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                    rowView(row, selected: index == selected)
                                        .id(index)
                                        .onTapGesture { selected = index; open(rows) }
                                }
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 320)
                        .fixedSize(horizontal: false, vertical: true)
                        .onChange(of: selected) { proxy.scrollTo(selected) }
                    }
                }
                footer(hasRows: !rows.isEmpty)
            }
            .frame(width: 600)
            .floatingPanel(cornerRadius: Metrics.paletteRadius, fill: .paper)
            .shadow(color: .black.opacity(0.14), radius: 30, y: 20)
            .padding(.top, 110)
        }
        .onAppear { focused = true }
    }

    private func rowView(_ row: Row, selected: Bool) -> some View {
        HStack {
            Text(row.name).lineLimit(1)
            Spacer(minLength: 12)
            Text(row.folder)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.accentText.opacity(0.8) : Color.ink3)
                .lineLimit(1)
        }
        .font(.system(size: 15))
        .foregroundStyle(selected ? Color.accentText : Color.ink)
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(selected ? Color.accentSoft : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
    }

    private func footer(hasRows: Bool) -> some View {
        HStack(spacing: 20) {
            if hasRows {
                Text("↑↓ select")
                Text("⏎ open")
            }
            if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("⌘⏎ new note “\(query.trimmingCharacters(in: .whitespaces))”").lineLimit(1)
            }
            Spacer()
            Text("esc")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.ink3)
        .padding(.horizontal, 22)
        .padding(.vertical, 11)
        .background(Color.paper2)
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func open(_ rows: [Row]) {
        guard rows.indices.contains(selected) else {
            if !query.trimmingCharacters(in: .whitespaces).isEmpty { create() }
            return
        }
        library.open(rows[selected].id)
        close()
    }

    private func create() {
        let title = query
        close()
        library.newNote(titled: title)
    }

    private func close() {
        library.isQuickOpenPresented = false
    }

    private static func rows(paths: [String], query: String) -> [Row] {
        fuzzyMatch(candidates: paths, query: query, limit: 50).map { match in
            let path = paths[Int(match.index)]
            return Row(id: path, name: name(path, positions: match.positions), folder: LibraryTree.parent(of: path))
        }
    }

    /// The note's name with matched characters bold.
    private static func name(_ path: String, positions: [UInt32]) -> AttributedString {
        let full = path as NSString
        let slash = full.range(of: "/", options: .backwards)
        let start = slash.location == NSNotFound ? 0 : slash.location + 1
        let name = (full.substring(from: start) as NSString).deletingPathExtension as NSString
        let text = NSMutableAttributedString(string: name as String, attributes: [.font: NSFont.systemFont(ofSize: 15)])
        for p in positions {
            let i = Int(p) - start
            if i >= 0, i < name.length {
                text.addAttribute(.font, value: NSFont.systemFont(ofSize: 15, weight: .bold), range: NSRange(location: i, length: 1))
            }
        }
        return (try? AttributedString(text, including: \.appKit)) ?? AttributedString(name as String)
    }
}
