import AppKit
import MdCore
import XCTest
@testable import Scribe

@MainActor
final class LivePreviewTests: XCTestCase {
    /// What the reader sees: hidden characters dropped, decorations shown as ⟨kind⟩.
    private func visible(_ text: String, caret: Int?, base: URL? = nil) -> String {
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter()
        highlighter.baseURL = base
        highlighter.resetCaret(caret)
        highlighter.highlightAll(storage)
        return render(storage)
    }

    private func render(_ storage: NSTextStorage) -> String {
        var out = ""
        let ns = storage.string as NSString
        for i in 0..<storage.length {
            if let d = storage.attribute(.scribeDecoration, at: i, effectiveRange: nil) as? Decoration {
                switch d.placement {
                case .inline: out += "⟨math⟩"
                case .block: out += "⟨block⟩"
                case .below: out += "⟨preview⟩"
                }
            }
            let font = storage.attribute(.font, at: i, effectiveRange: nil) as? NSFont
            if (font?.pointSize ?? 16) >= 1 { out += ns.substring(with: NSRange(location: i, length: 1)) }
        }
        return out
    }

    func testInlineMarkersHiddenUntilCaretTouches() {
        let text = "a **bold** and *it* c"
        XCTAssertEqual(visible(text, caret: 0), "a bold and it c")
        XCTAssertEqual(visible(text, caret: 4), "a **bold** and it c")
        XCTAssertEqual(visible(text, caret: 10), "a **bold** and it c", "touching the end counts")
        XCTAssertEqual(visible(text, caret: 11), "a bold and it c")
    }

    func testHeadingRevealsOnItsLine() {
        let text = "## Title\nbody"
        XCTAssertEqual(visible(text, caret: 12), "Title\nbody")
        XCTAssertEqual(visible(text, caret: 5), "## Title\nbody")
    }

    func testLinksHideUrl() {
        XCTAssertEqual(visible("see [docs](https://x.y) ok", caret: 0), "see docs ok")
    }

    func testRangeSelectionDoesNotReveal() {
        let storage = NSTextStorage(string: "x **b** y")
        let highlighter = MarkdownHighlighter()
        highlighter.resetCaret(0)
        highlighter.highlightAll(storage)
        highlighter.selectionDidChange(storage, selection: NSRange(location: 0, length: 6))
        XCTAssertEqual(render(storage), "x b y")
        highlighter.selectionDidChange(storage, selection: NSRange(location: 4, length: 0))
        XCTAssertEqual(render(storage), "x **b** y")
        highlighter.selectionDidChange(storage, selection: NSRange(location: 9, length: 0))
        XCTAssertEqual(render(storage), "x b y")
    }

    func testInlineMathRendersWhenInactive() {
        let text = "f $x^2$ g"
        XCTAssertEqual(visible(text, caret: 0), "f ⟨math⟩ g")
        XCTAssertEqual(visible(text, caret: 4), "f $x^2$ g")
    }

    func testInvalidMathStaysAsRedSource() {
        let text = "f $\\nosuchcommand x$ g"
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter()
        highlighter.resetCaret(0)
        highlighter.highlightAll(storage)
        XCTAssertEqual(render(storage), text)
        XCTAssertEqual(storage.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor, .systemRed)
        XCTAssertNotNil(storage.attribute(.toolTip, at: 4, effectiveRange: nil))
    }

    func testBlockMathCollapsesToOneDecoratedLine() {
        let text = "a\n\n$$\nx^2\n$$\n\nb"
        XCTAssertEqual(visible(text, caret: 0), "a\n\n⟨block⟩\nb")
        XCTAssertEqual(visible(text, caret: 6), "a\n\n$$\nx^2\n⟨preview⟩$$\n\nb", "editing shows source plus preview")
    }

    func testFencedCodeHidesFences() {
        let text = "```swift\nlet x = 1\n```\nafter"
        XCTAssertEqual(visible(text, caret: text.utf16.count), "let x = 1\nafter")
        XCTAssertEqual(visible(text, caret: 10), text)
    }

    func testQuoteHidesMarkers() {
        XCTAssertEqual(visible("> quoted\n\nx", caret: 10), "quoted\n\nx")
    }

    func testListsAndTablesAlwaysShowSource() {
        let text = "- [ ] task\n\n| a |\n|---|\n| 1 |"
        XCTAssertEqual(visible(text, caret: nil), text)
    }

    func testStandaloneImageRendersFromRelativePath() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("assets"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let image = NSImage(size: NSSize(width: 40, height: 20), flipped: false) { r in
            NSColor.red.setFill(); r.fill(); return true
        }
        let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try png.write(to: dir.appendingPathComponent("assets/my pic.png"))

        let text = "intro\n![pic](assets/my%20pic.png)\nend"
        XCTAssertEqual(visible(text, caret: 0, base: dir), "intro\n⟨block⟩end")
        XCTAssertEqual(visible("![x](missing.png)", caret: nil, base: dir), "x", "missing file: just hide markers")
    }

    func testTypingAtEndOfBoldKeepsItRevealed() {
        let storage = NSTextStorage(string: "**b**")
        let highlighter = MarkdownHighlighter()
        highlighter.resetCaret(5)
        highlighter.highlightAll(storage)
        storage.replaceCharacters(in: NSRange(location: 5, length: 0), with: " x")
        highlighter.textDidChange(storage, editedRange: NSRange(location: 5, length: 2), changeInLength: 2)
        highlighter.selectionDidChange(storage, selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(render(storage), "b x")
    }
}

final class PresentationTests: XCTestCase {
    func testImageURLParsing() {
        let base = URL(fileURLWithPath: "/notes")
        func url(_ md: String) -> String? {
            let span = parseMarkdown(text: md).first { if case .image = $0.kind { true } else { false } }!
            return Presentation.imageURL(of: span, in: md as NSString, base: base)?.path
        }
        XCTAssertEqual(url("![a](img/x.png)"), "/notes/img/x.png")
        XCTAssertEqual(url("![a](<my pic.png> \"t\")"), "/notes/my pic.png")
        XCTAssertEqual(url("![a](x.png \"title\")"), "/notes/x.png")
        XCTAssertEqual(url("![a](/abs/y.png)"), "/abs/y.png")
        XCTAssertNil(url("![a](https://example.com/z.png)"))
    }
}
