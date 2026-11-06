import AppKit
import XCTest
@testable import Scribe

final class FormattingTests: XCTestCase {
    /// Applies an edit; `|` marks the caret, `[…]` the selection, in both input and output.
    private func run(_ input: String, _ command: (NSString, NSRange) -> TextEdit) -> String {
        var text = input
        var selection = NSRange(location: 0, length: 0)
        if let open = text.firstIndex(of: "["), let close = text.firstIndex(of: "]"), text.contains("[") && !text.contains("|") {
            let start = text.utf16.distance(from: text.startIndex, to: open)
            let end = text.utf16.distance(from: text.startIndex, to: close) - 1
            text.remove(at: close); text.remove(at: open)
            selection = NSRange(location: start, length: end - start)
        } else if let bar = text.firstIndex(of: "|") {
            selection = NSRange(location: text.utf16.distance(from: text.startIndex, to: bar), length: 0)
            text.remove(at: bar)
        }
        let edit = command(text as NSString, selection)
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.range, with: edit.replacement)
        if edit.selection.length == 0 {
            result.insert("|", at: edit.selection.location)
        } else {
            result.insert("]", at: NSMaxRange(edit.selection))
            result.insert("[", at: edit.selection.location)
        }
        return result as String
    }

    private func wrap(_ marker: String) -> (NSString, NSRange) -> TextEdit {
        { Formatting.toggleWrap(marker, text: $0, selection: $1) }
    }

    func testBoldWrapsAndUnwraps() {
        XCTAssertEqual(run("a [word] b", wrap("**")), "a **[word]** b")
        XCTAssertEqual(run("a **[word]** b", wrap("**")), "a [word] b")
        XCTAssertEqual(run("a [**word**] b", wrap("**")), "a [word] b")
    }

    func testEmptySelectionInsertsPair() {
        XCTAssertEqual(run("a | b", wrap("**")), "a **|** b")
    }

    func testTrailingSpaceIsNotWrapped() {
        XCTAssertEqual(run("[word ]b", wrap("*")), "*[word]* b")
    }

    func testItalicInsideBoldIsNotMistakenForItalic() {
        XCTAssertEqual(run("**[x]**", wrap("*")), "***[x]***")
        XCTAssertEqual(run("***[x]***", wrap("*")), "**[x]**")
        XCTAssertEqual(run("***[x]***", wrap("**")), "*[x]*")
    }

    func testMathInlineAndBlock() {
        XCTAssertEqual(run("[x^2]", { Formatting.toggleMath(text: $0, selection: $1) }), "$[x^2]$")
        XCTAssertEqual(run("[a\nb]", { Formatting.toggleMath(text: $0, selection: $1) }), "[$$\na\nb\n$$]")
    }

    func testLink() {
        let link: (NSString, NSRange) -> TextEdit = { Formatting.insertLink(text: $0, selection: $1) }
        XCTAssertEqual(run("see [docs]", link), "see [docs]([url])")
        XCTAssertEqual(run("[https://x.y]", link), "[|](https://x.y)")
        XCTAssertEqual(run("a |", link), "a [|]()")
    }

    func testHeadings() {
        let h2: (NSString, NSRange) -> TextEdit = { Formatting.setHeading(2, text: $0, selection: $1) }
        let h1: (NSString, NSRange) -> TextEdit = { Formatting.setHeading(1, text: $0, selection: $1) }
        XCTAssertEqual(run("Tit|le\nbody", h2), "## Tit|le\nbody")
        XCTAssertEqual(run("## Tit|le\nbody", h2), "Tit|le\nbody", "same level toggles off")
        XCTAssertEqual(run("## Tit|le", h1), "# Tit|le")
        XCTAssertEqual(run("#|# Title", h2), "|Title")
    }

    func testHeadingLevelParsing() {
        XCTAssertEqual(Formatting.headingLevel("### x"), 3)
        XCTAssertEqual(Formatting.headingLevel("#hashtag"), 0)
        XCTAssertEqual(Formatting.headingLevel("####### seven"), 0)
    }
}

@MainActor
final class MarkdownTextViewTests: XCTestCase {
    func testActionsEditTheText() {
        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.string = "hello world"
        view.setSelectedRange(NSRange(location: 6, length: 5))
        view.toggleBold(nil)
        XCTAssertEqual(view.string, "hello **world**")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 8, length: 5))
        view.setHeadingLevel(NSNumber(value: 1))
        XCTAssertEqual(view.string, "# hello **world**")
    }
}

@MainActor
final class SearchModelTests: XCTestCase {
    func testFindsNotesInBackground() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "# Zakupy\nmleko, chleb\n".write(to: dir.appendingPathComponent("Zakupy.md"), atomically: true, encoding: .utf8)
        try "Nic tu nie ma\n".write(to: dir.appendingPathComponent("Inne.md"), atomically: true, encoding: .utf8)

        let model = SearchModel()
        model.open(root: dir)
        model.query = "CHLEB"
        for _ in 0..<50 where model.results.isEmpty {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.results.map(\.relativePath), ["Zakupy.md"])
        XCTAssertEqual(model.results.first?.lines.first?.line, 1)

        model.query = ""
        XCTAssertTrue(model.results.isEmpty)
    }
}
