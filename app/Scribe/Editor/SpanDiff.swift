import Foundation
import MdCore

extension Utf16Range {
    var nsRange: NSRange { NSRange(location: Int(start), length: Int(end) - Int(start)) }
}

/// Finds the part of the document whose styling may have changed after an edit,
/// so only that part is restyled.
enum SpanDiff {
    /// - Parameters:
    ///   - old: spans before the edit (old coordinates)
    ///   - new: spans after the edit
    ///   - edited: range of the edit in new coordinates (`NSTextStorage.editedRange`)
    ///   - delta: change in length (`NSTextStorage.changeInLength`)
    /// - Returns: range in new coordinates covering the edit and every span that differs.
    static func dirtyRange(old: [MarkdownSpan], new: [MarkdownSpan], edited: NSRange, delta: Int) -> NSRange {
        let editEndOld = edited.location + edited.length - delta
        let shifted = old.map { shift($0, from: editEndOld, by: delta) }

        var prefix = 0
        while prefix < shifted.count, prefix < new.count, shifted[prefix] == new[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < shifted.count - prefix, suffix < new.count - prefix,
              shifted[shifted.count - 1 - suffix] == new[new.count - 1 - suffix] {
            suffix += 1
        }

        var dirty = edited
        for span in shifted[prefix..<(shifted.count - suffix)] { dirty = union(dirty, span.range) }
        for span in new[prefix..<(new.count - suffix)] { dirty = union(dirty, span.range) }
        return dirty
    }

    private static func shift(_ span: MarkdownSpan, from position: Int, by delta: Int) -> MarkdownSpan {
        guard delta != 0 else { return span }
        func move(_ r: Utf16Range) -> Utf16Range {
            func p(_ x: UInt32) -> UInt32 { Int(x) >= position ? UInt32(max(0, Int(x) + delta)) : x }
            return Utf16Range(start: p(r.start), end: p(r.end))
        }
        return MarkdownSpan(kind: span.kind, range: move(span.range), markers: span.markers.map(move))
    }

    private static func union(_ a: NSRange, _ b: Utf16Range) -> NSRange {
        let start = min(a.location, Int(b.start))
        let end = max(a.location + a.length, Int(b.end))
        return NSRange(location: start, length: max(0, end - start))
    }
}
