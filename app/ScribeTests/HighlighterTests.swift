import AppKit
import MdCore
import XCTest
@testable import Scribe

@MainActor
final class HighlighterTests: XCTestCase {
    private let theme = MarkdownTheme.standard

    private func styled(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownHighlighter(theme: theme).highlightAll(storage)
        return storage
    }

    private func font(_ s: NSTextStorage, at i: Int) -> NSFont {
        s.attribute(.font, at: i, effectiveRange: nil) as! NSFont
    }

    private func color(_ s: NSTextStorage, at i: Int) -> NSColor? {
        s.attribute(.foregroundColor, at: i, effectiveRange: nil) as? NSColor
    }

    private func traits(_ s: NSTextStorage, at i: Int) -> NSFontTraitMask {
        NSFontManager.shared.traits(of: font(s, at: i))
    }

    func testHeadingIsLargerAndBoldWithDimmedMarker() {
        let s = styled("## Title\nbody")
        XCTAssertGreaterThan(font(s, at: 3).pointSize, theme.fontSize)
        XCTAssertTrue(traits(s, at: 3).contains(.boldFontMask))
        XCTAssertEqual(color(s, at: 0), theme.markerColor)
        XCTAssertEqual(color(s, at: 3), theme.textColor)
        XCTAssertEqual(font(s, at: 10).pointSize, theme.fontSize, "body after heading is plain")
    }

    func testNestedEmphasisAccumulatesTraits() {
        let s = styled("***both*** and *it*")
        let t = traits(s, at: 4)
        XCTAssertTrue(t.contains(.boldFontMask) && t.contains(.italicFontMask))
        XCTAssertEqual(color(s, at: 0), theme.markerColor)
        XCTAssertTrue(traits(s, at: 16).contains(.italicFontMask))
        XCTAssertFalse(traits(s, at: 11).contains(.italicFontMask))
    }

    func testCodeAndMathAreMonospaced() {
        let s = styled("`x` and $y$")
        XCTAssertTrue(font(s, at: 1).isFixedPitch)
        XCTAssertTrue(font(s, at: 9).isFixedPitch)
        XCTAssertEqual(color(s, at: 9), theme.mathColor)
        XCTAssertEqual(color(s, at: 8), theme.markerColor)
    }

    func testLinkTextColoredAndUrlDimmed() {
        let s = styled("[docs](https://x.y)")
        XCTAssertEqual(color(s, at: 2), theme.linkColor)
        XCTAssertEqual(color(s, at: 10), theme.markerColor)
    }

    func testEditRestylesIncrementally() {
        let storage = NSTextStorage(string: "plain\n\nother")
        let highlighter = MarkdownHighlighter(theme: theme)
        highlighter.highlightAll(storage)

        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "# ")
        highlighter.textDidChange(storage, editedRange: NSRange(location: 0, length: 2), changeInLength: 2)
        XCTAssertTrue(traits(storage, at: 3).contains(.boldFontMask))
        XCTAssertEqual(color(storage, at: 0), theme.markerColor)

        storage.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        highlighter.textDidChange(storage, editedRange: NSRange(location: 0, length: 0), changeInLength: -2)
        XCTAssertFalse(traits(storage, at: 1).contains(.boldFontMask))
        XCTAssertEqual(color(storage, at: 0), theme.textColor)
    }

    func testOpeningFenceRestylesTheRest() {
        let storage = NSTextStorage(string: "a\n\nb\n\nc")
        let highlighter = MarkdownHighlighter(theme: theme)
        highlighter.highlightAll(storage)
        storage.replaceCharacters(in: NSRange(location: 0, length: 0), with: "```\n")
        highlighter.textDidChange(storage, editedRange: NSRange(location: 0, length: 4), changeInLength: 4)
        XCTAssertTrue(font(storage, at: storage.length - 1).isFixedPitch, "unclosed fence extends to the end")
    }
}

final class SpanDiffTests: XCTestCase {
    private func span(_ kind: SpanKind, _ s: UInt32, _ e: UInt32) -> MarkdownSpan {
        MarkdownSpan(kind: kind, range: Utf16Range(start: s, end: e), markers: [])
    }

    func testTypingInPlainTextOnlyDirtiesTheEdit() {
        let old = [span(.strong, 0, 8), span(.emphasis, 20, 25)]
        // Insert 3 chars at 10: the emphasis shifts but is otherwise unchanged.
        let new = [span(.strong, 0, 8), span(.emphasis, 23, 28)]
        let dirty = SpanDiff.dirtyRange(old: old, new: new, edited: NSRange(location: 10, length: 3), delta: 3)
        XCTAssertEqual(dirty, NSRange(location: 10, length: 3))
    }

    func testSpanGrowingByTheInsertionNeedsOnlyTheEdit() {
        // Typing inside **bold**: shifted old span equals the new one.
        let old = [span(.strong, 0, 8)]
        let new = [span(.strong, 0, 9)]
        let dirty = SpanDiff.dirtyRange(old: old, new: new, edited: NSRange(location: 4, length: 1), delta: 1)
        XCTAssertEqual(dirty, NSRange(location: 4, length: 1))
    }

    func testChangedSpanIsIncluded() {
        // Typing `*` after `**ab*` closes the strong span: a span appears.
        let old = [span(.emphasis, 30, 40)]
        let new = [span(.strong, 0, 6), span(.emphasis, 31, 41)]
        let dirty = SpanDiff.dirtyRange(old: old, new: new, edited: NSRange(location: 5, length: 1), delta: 1)
        XCTAssertEqual(dirty, NSRange(location: 0, length: 6))
    }

    func testRemovedSpanIsIncluded() {
        let old = [span(.codeBlock, 0, 100)]
        let dirty = SpanDiff.dirtyRange(old: old, new: [], edited: NSRange(location: 0, length: 0), delta: -3)
        XCTAssertEqual(dirty, NSRange(location: 0, length: 97), "old span in new coordinates")
    }
}
