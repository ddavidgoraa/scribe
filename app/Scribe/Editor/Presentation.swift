import Foundation
import MdCore

/// Pure rules for live preview: which elements show their source, and what to extract
/// from them. Elements are *active* (markers revealed) while the caret touches them.
enum Presentation {
    /// Whether `span` shows its source for the given caret (`nil` = no caret, e.g. a
    /// range selection). Touching counts: a caret right before or after the element.
    static func isActive(_ span: MarkdownSpan, caret: Int?) -> Bool {
        guard let caret else { return false }
        return Int(span.range.start) <= caret && caret <= Int(span.range.end)
    }

    /// Whether the span hides markers when inactive. Lists, tables, task boxes, rules,
    /// footnote definitions and HTML always show their source.
    static func hidesMarkers(_ kind: SpanKind) -> Bool {
        switch kind {
        case .heading, .emphasis, .strong, .strikethrough, .code, .link, .footnoteReference,
             .image, .math, .mathBlock, .codeBlock, .blockQuote:
            true
        case .listItem, .taskMarker, .table, .thematicBreak, .footnoteDefinition, .html:
            false
        }
    }

    /// Whether printing replaces the span's visible syntax with a typeset form.
    static func typesetForPrint(_ kind: SpanKind) -> Bool {
        switch kind {
        case .listItem, .taskMarker, .thematicBreak: true
        default: false
        }
    }

    /// Whether `range` occupies whole lines (starts at a line start, ends at a line end).
    static func isStandalone(_ range: NSRange, in text: NSString) -> Bool {
        let startsLine = range.location == 0 || text.character(at: range.location - 1) == 0x0A
        let end = NSMaxRange(range)
        let endsLine = end == text.length || text.character(at: end) == 0x0A
        return startsLine && endsLine
    }

    /// Text between the first and last marker (e.g. the LaTeX of `$…$`), trimmed.
    static func content(of span: MarkdownSpan, in text: NSString) -> String {
        let start = span.markers.first.map { Int($0.end) } ?? Int(span.range.start)
        let end = span.markers.count > 1 ? Int(span.markers.last!.start) : Int(span.range.end)
        guard end > start else { return "" }
        return text.substring(with: NSRange(location: start, length: end - start))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Local file path of an image (`![alt](path "title")`), resolved against `base`.
    /// Remote URLs are not loaded.
    static func imageURL(of span: MarkdownSpan, in text: NSString, base: URL?) -> URL? {
        guard let closing = span.markers.last else { return nil }
        var source = text.substring(with: closing.nsRange) // `](path "title")`
        guard source.hasPrefix("]("), source.hasSuffix(")") else { return nil }
        source = String(source.dropFirst(2).dropLast()).trimmingCharacters(in: .whitespaces)
        if source.hasPrefix("<"), let end = source.firstIndex(of: ">") {
            source = String(source[source.index(after: source.startIndex)..<end])
        } else if let space = source.firstIndex(of: " ") {
            source = String(source[..<space])
        }
        let path = source.removingPercentEncoding ?? source
        guard !path.isEmpty, !path.contains("://") || path.hasPrefix("file://") else { return nil }
        if path.hasPrefix("file://") { return URL(string: path) }
        if path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        if path.hasPrefix("~") { return URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        return base?.appendingPathComponent(path).standardizedFileURL
    }
}
