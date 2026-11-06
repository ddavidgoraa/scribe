import MdCore
import SwiftUI

/// Library-wide search results in the sidebar: notes, then matching lines.
struct SearchResultsView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let results = library.search.results
        List {
            if results.isEmpty {
                Text(library.search.isSearching ? "Searching…" : "No Results")
                    .foregroundStyle(.secondary)
            }
            ForEach(results, id: \.relativePath) { hit in
                Section {
                    ForEach(hit.lines, id: \.line) { line in
                        Button {
                            library.open(hit.relativePath, revealing: line.matchRange.nsRange)
                        } label: {
                            Text(highlighted(line.snippet, line.ranges))
                                .lineLimit(2)
                                .font(.callout)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Button {
                        library.open(hit.relativePath)
                    } label: {
                        Label(title(hit.relativePath), systemImage: "doc.text")
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func title(_ path: String) -> String {
        (path as NSString).deletingPathExtension
    }
}

/// `text` with `ranges` (UTF-16) emphasized.
func highlighted(_ text: String, _ ranges: [Utf16Range]) -> AttributedString {
    let attributed = NSMutableAttributedString(string: text)
    for range in ranges {
        let r = NSIntersectionRange(range.nsRange, NSRange(location: 0, length: attributed.length))
        guard r.length > 0 else { continue }
        attributed.addAttributes([
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.controlAccentColor,
        ], range: r)
    }
    return (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString(text)
}
