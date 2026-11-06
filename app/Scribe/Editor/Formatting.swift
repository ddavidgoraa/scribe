import Foundation

/// A text change produced by a formatting command.
struct TextEdit: Equatable {
    var range: NSRange
    var replacement: String
    /// Selection after applying the edit.
    var selection: NSRange
}

/// Markdown formatting commands as pure functions of (text, selection).
enum Formatting {
    /// Wraps the selection in `marker` (`**`, `*`, `~~`, `$`), or unwraps it if it
    /// is already wrapped. With no selection, inserts an empty pair around the caret
    /// (or removes one the caret is inside).
    static func toggleWrap(_ marker: String, text: NSString, selection: NSRange) -> TextEdit {
        let m = (marker as NSString).length
        var sel = trimTrailingWhitespace(selection, in: text)

        // Wrapped from outside: **|sel|**
        if runLength(of: marker, before: sel.location, in: text).matches(m, marker: marker),
           runLength(of: marker, after: NSMaxRange(sel), in: text).matches(m, marker: marker) {
            let outer = NSRange(location: sel.location - m, length: sel.length + 2 * m)
            return TextEdit(range: outer, replacement: text.substring(with: sel),
                            selection: NSRange(location: outer.location, length: sel.length))
        }
        // Wrapped inside the selection: |**sel**|
        if sel.length >= 2 * m {
            let inner = NSRange(location: sel.location + m, length: sel.length - 2 * m)
            if text.substring(with: NSRange(location: sel.location, length: m)) == marker,
               text.substring(with: NSRange(location: NSMaxRange(sel) - m, length: m)) == marker,
               inner.length > 0 || sel.length == 2 * m {
                return TextEdit(range: sel, replacement: text.substring(with: inner),
                                selection: NSRange(location: sel.location, length: inner.length))
            }
        }
        if sel.length == 0 { sel = selection }
        let inner = text.substring(with: sel)
        return TextEdit(range: sel, replacement: marker + inner + marker,
                        selection: NSRange(location: sel.location + m, length: sel.length))
    }

    /// Math: `$…$` inline, `$$` block when the selection spans lines.
    static func toggleMath(text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        guard selected.contains("\n") else { return toggleWrap("$", text: text, selection: selection) }
        let block = "$$\n" + selected.trimmingCharacters(in: .newlines) + "\n$$"
        return TextEdit(range: selection, replacement: block,
                        selection: NSRange(location: selection.location, length: (block as NSString).length))
    }

    /// `[selection](url)` with `url` selected; a selected URL becomes the target;
    /// nothing selected gives `[]()` with the caret in the brackets.
    static func insertLink(text: NSString, selection: NSRange) -> TextEdit {
        let selected = text.substring(with: selection)
        if selected.isEmpty {
            return TextEdit(range: selection, replacement: "[]()",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        if let url = URL(string: selected), url.scheme != nil, !selected.contains(" ") {
            return TextEdit(range: selection, replacement: "[](\(selected))",
                            selection: NSRange(location: selection.location + 1, length: 0))
        }
        let urlStart = selection.location + (selected as NSString).length + 3
        return TextEdit(range: selection, replacement: "[\(selected)](url)",
                        selection: NSRange(location: urlStart, length: 3))
    }

    /// Sets the heading level of the selected lines; the same level again removes it.
    static func setHeading(_ level: Int, text: NSString, selection: NSRange) -> TextEdit {
        let lines = text.lineRange(for: selection)
        let original = text.substring(with: lines)
        let hasNewline = original.hasSuffix("\n")
        var rows = original.components(separatedBy: "\n")
        if hasNewline { rows.removeLast() }

        let current = rows.first.map(headingLevel) ?? 0
        let target = current == level ? 0 : level
        var delta = 0
        rows = rows.enumerated().map { index, row in
            let stripped = stripHeading(row)
            let new = target == 0 || stripped.isEmpty && rows.count > 1 ? stripped
                : String(repeating: "#", count: target) + " " + stripped
            if index == 0 { delta = (new as NSString).length - (row as NSString).length }
            return new
        }
        let replacement = rows.joined(separator: "\n") + (hasNewline ? "\n" : "")
        let newSelection = selection.length > 0
            ? NSRange(location: lines.location, length: (replacement as NSString).length - (hasNewline ? 1 : 0))
            : NSRange(location: max(lines.location, selection.location + delta), length: 0)
        return TextEdit(range: lines, replacement: replacement, selection: newSelection)
    }

    // MARK: Helpers

    static func headingLevel(_ line: String) -> Int {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return 0 }
        let rest = line.dropFirst(hashes)
        return rest.isEmpty || rest.first == " " ? hashes : 0
    }

    private static func stripHeading(_ line: String) -> String {
        let level = headingLevel(line)
        guard level > 0 else { return line }
        return String(line.dropFirst(level).drop { $0 == " " })
    }

    private struct Run {
        let count: Int
        /// `*` runs of 3 contain both `*` and `**`.
        func matches(_ length: Int, marker: String) -> Bool {
            count == length || (marker.hasPrefix("*") && count >= 3)
        }
    }

    private static func runLength(of marker: String, before index: Int, in text: NSString) -> Run {
        let c = (marker as NSString).character(at: 0)
        var i = index, n = 0
        while i > 0, text.character(at: i - 1) == c { i -= 1; n += 1 }
        return Run(count: n)
    }

    private static func runLength(of marker: String, after index: Int, in text: NSString) -> Run {
        let c = (marker as NSString).character(at: 0)
        var i = index, n = 0
        while i < text.length, text.character(at: i) == c { i += 1; n += 1 }
        return Run(count: n)
    }

    private static func trimTrailingWhitespace(_ range: NSRange, in text: NSString) -> NSRange {
        var r = range
        while r.length > 0, let scalar = UnicodeScalar(text.character(at: NSMaxRange(r) - 1)),
              CharacterSet.whitespacesAndNewlines.contains(scalar) {
            r.length -= 1
        }
        return r
    }
}
