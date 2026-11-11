import MdCore
import SwiftUI

/// Library search results in the panel: a card per note, matches marked like a highlighter.
struct SearchResultsView: View {
    @Environment(LibraryModel.self) private var library

    var body: some View {
        let results = library.search.results
        if results.isEmpty {
            Text(library.search.isSearching ? "Searching…" : "No results")
                .font(.system(size: 13))
                .foregroundStyle(Color.ink3)
                .padding(.horizontal, 8)
                .padding(.top, 6)
        }
        ForEach(results, id: \.relativePath) { hit in
            card(hit)
        }
    }

    private func card(_ hit: SearchHit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { library.open(hit.relativePath) } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text(((hit.relativePath as NSString).lastPathComponent as NSString).deletingPathExtension)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Spacer(minLength: 6)
                    Text([LibraryTree.parent(of: hit.relativePath), countLabel(hit)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .lineLimit(1)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(hit.lines, id: \.line) { line in
                Button { library.open(hit.relativePath, revealing: line.matchRange.nsRange) } label: {
                    Text(marked(line.snippet, line.ranges))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.ink2)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line))
        .padding(.bottom, 6)
    }

    private func countLabel(_ hit: SearchHit) -> String {
        switch hit.lines.count {
        case 0: hit.titleMatch ? "title" : ""
        case 1: "1 match"
        case 5: "5+ matches"
        default: "\(hit.lines.count) matches"
        }
    }
}

/// `text` with `ranges` (UTF-16) marked with a highlighter background.
func marked(_ text: String, _ ranges: [Utf16Range]) -> AttributedString {
    let attributed = NSMutableAttributedString(string: text)
    for range in ranges {
        let r = NSIntersectionRange(range.nsRange, NSRange(location: 0, length: attributed.length))
        guard r.length > 0 else { continue }
        attributed.addAttributes([.backgroundColor: Palette.mark, .foregroundColor: Palette.ink], range: r)
    }
    return (try? AttributedString(attributed, including: \.appKit)) ?? AttributedString(text)
}
