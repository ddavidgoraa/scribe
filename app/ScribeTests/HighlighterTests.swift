import AppKit
import MdCore
import XCTest
@testable import Scribe

@MainActor
final class HighlighterTests: XCTestCase {
    private let theme = MarkdownTheme.standard

    /// Styles `text` with the caret at `caret` (`nil`: no element active, markers hidden).
    private func styled(_ text: String, caret: Int? = nil) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        let highlighter = MarkdownHighlighter(theme: theme)
        highlighter.resetCaret(caret)
        highlighter.highlightAll(storage)
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
        let s = styled("## Title\nbody", caret: 3)
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
        XCTAssertEqual(color(s, at: 0), .clear, "inactive markers are hidden")
        XCTAssertTrue(traits(s, at: 16).contains(.italicFontMask))
        XCTAssertFalse(traits(s, at: 11).contains(.italicFontMask))
    }

    func testCodeAndMathAreMonospaced() {
        let s = styled("`x` and $y$", caret: 9)
        XCTAssertTrue(font(s, at: 1).isCodeFont)
        XCTAssertTrue(font(s, at: 9).isCodeFont)
        XCTAssertEqual(color(s, at: 9), theme.mathColor)
        XCTAssertEqual(color(s, at: 8), theme.markerColor)
    }

    func testLinkTextColoredAndUrlDimmed() {
        let s = styled("[docs](https://x.y)", caret: 2)
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
        XCTAssertEqual(color(storage, at: 0), theme.markerColor, "caret after the edit reveals the marker")

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
        XCTAssertTrue(font(storage, at: storage.length - 1).isCodeFont, "unclosed fence extends to the end")
    }
}

private extension NSFont {
    /// Code is set in SF Mono.
    var isCodeFont: Bool { isFixedPitch }
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

@MainActor
final class ThemeTests: XCTestCase {
    private func traits(_ font: NSFont) -> NSFontDescriptor.SymbolicTraits { font.fontDescriptor.symbolicTraits }

    func testSystemFamilies() {
        XCTAssertFalse(EditorFont.sans.font(size: 16).isFixedPitch)
        XCTAssertTrue(EditorFont.mono.font(size: 16).isFixedPitch, "SF Mono")
        let serif = EditorFont.serif.font(size: 16)
        XCTAssertNotEqual(serif.familyName, EditorFont.sans.font(size: 16).familyName, "New York, not SF Pro")
        XCTAssertFalse(serif.isFixedPitch)
        for family in EditorFont.allCases {
            let font = family.font(size: 16, bold: true, italic: true)
            XCTAssertTrue(traits(font).contains(.bold), "\(family) bold")
            XCTAssertTrue(traits(font).contains(.italic), "\(family) italic")
        }
    }

    func testTraitsKeepTheFamily() {
        for family in EditorFont.allCases {
            let regular = family.font(size: 16)
            let bold = EditorFonts.adding(bold: true, to: regular)
            let boldItalic = EditorFonts.adding(italic: true, to: bold)
            XCTAssertEqual(bold.familyName, regular.familyName, "\(family)")
            XCTAssertEqual(boldItalic.familyName, regular.familyName, "\(family)")
            XCTAssertTrue(traits(boldItalic).contains([.bold, .italic]))
        }
    }

    func testOldFontSettingsFallBackToTheDefault() {
        XCTAssertEqual(EditorFont(storedValue: "duo"), .sans)
        XCTAssertEqual(EditorFont(storedValue: "quattro"), .sans)
        XCTAssertEqual(EditorFont(storedValue: nil), .sans)
        XCTAssertEqual(EditorFont(storedValue: "serif"), .serif)
    }

    func testColumnIsAbout64Characters() {
        let theme = MarkdownTheme(font: .sans, fontSize: 16)
        XCTAssertGreaterThan(theme.columnWidth, 450)
        XCTAssertLessThan(theme.columnWidth, 700)
        XCTAssertGreaterThan(MarkdownTheme(font: .sans, fontSize: 20).columnWidth, theme.columnWidth)
    }

    func testFocusBlockSpansLinesBetweenBlankLines() {
        let text = "first\n\nline a\nline b\n\nlast" as NSString
        let block = MarkdownTextView.block(around: 10, in: text)
        XCTAssertEqual(text.substring(with: block), "line a\nline b\n")
        XCTAssertEqual(text.substring(with: MarkdownTextView.block(around: 6, in: text)), "\n", "blank line is its own block")
        XCTAssertEqual(MarkdownTextView.block(around: 0, in: ""), NSRange(location: 0, length: 0))
    }

    func testFocusDimsOtherParagraphs() {
        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.string = "one\n\ntwo"
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.focusMode = true
        XCTAssertFalse(view.isDimmed(NSRange(location: 5, length: 3)))
        XCTAssertTrue(view.isDimmed(NSRange(location: 0, length: 4)))
        view.focusMode = false
        XCTAssertFalse(view.isDimmed(NSRange(location: 0, length: 4)))
    }
}
