import MdCore
import SwiftUI

/// ⌘P: fuzzy-find a note by name or path.
struct QuickOpenView: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private struct Row: Identifiable {
        let id: String
        let display: AttributedString
    }

    var body: some View {
        let paths = library.notePaths
        let rows = Self.rows(paths: paths, query: query)
        VStack(spacing: 0) {
            TextField("Open Note", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .padding(12)
                .focused($focused)
                .onSubmit { open(rows) }
                .onKeyPress(.downArrow) { move(1, count: rows.count); return .handled }
                .onKeyPress(.upArrow) { move(-1, count: rows.count); return .handled }
                .onKeyPress(.escape) { dismiss(); return .handled }
                .onChange(of: query) { selected = 0 }
            Divider()
            ScrollViewReader { proxy in
                List(Array(rows.enumerated()), id: \.element.id) { index, row in
                    Text(row.display)
                        .lineLimit(1)
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .listRowBackground(index == selected ? Color.accentColor.opacity(0.2) : Color.clear)
                        .onTapGesture { selected = index; open(rows) }
                        .id(index)
                }
                .listStyle(.plain)
                .onChange(of: selected) { proxy.scrollTo(selected) }
            }
            if rows.isEmpty {
                Text("No matching notes").foregroundStyle(.secondary).padding()
            }
        }
        .frame(width: 520, height: 360)
        .onAppear { focused = true }
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selected = (selected + delta + count) % count
    }

    private func open(_ rows: [Row]) {
        guard rows.indices.contains(selected) else { return }
        library.open(rows[selected].id)
        dismiss()
    }

    private static func rows(paths: [String], query: String) -> [Row] {
        fuzzyMatch(candidates: paths, query: query, limit: 50).map { match in
            let path = paths[Int(match.index)]
            return Row(id: path, display: display(path, positions: match.positions))
        }
    }

    /// Folder in secondary color, name in primary; matched characters bold.
    private static func display(_ path: String, positions: [UInt32]) -> AttributedString {
        let shown = (path as NSString).deletingPathExtension as NSString
        let text = NSMutableAttributedString(string: shown as String, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ])
        let slash = shown.range(of: "/", options: .backwards)
        if slash.location != NSNotFound {
            text.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor,
                              range: NSRange(location: 0, length: slash.location + 1))
        }
        for p in positions where Int(p) < shown.length {
            text.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: NSRange(location: Int(p), length: 1))
        }
        return (try? AttributedString(text, including: \.appKit)) ?? AttributedString(shown as String)
    }
}
