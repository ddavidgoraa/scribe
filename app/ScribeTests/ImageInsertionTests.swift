import AppKit
import XCTest
@testable import Scribe

@MainActor
final class ImageInsertionTests: XCTestCase {
    private var root: URL!
    private var note: URL!
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Notes"), withIntermediateDirectories: true)
        note = root.appendingPathComponent("Notes/My Trip.md")
        try "".write(to: note, atomically: true, encoding: .utf8)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("scribe-test-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
    }

    private func pngData() -> Data {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

    func testScreenshotDataIsSavedToAssets() throws {
        pasteboard.setData(pngData(), forType: .png)
        let images = try ImageInsertion.images(from: pasteboard, note: note, libraryRoot: root, now: fixedDate)
        let stamp = ImageInsertion.timestamp(fixedDate)
        XCTAssertEqual(images, [ImageInsertion.Image(alt: "", link: "assets/My-Trip-\(stamp).png")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/assets/My-Trip-\(stamp).png").path))
    }

    func testTiffIsConvertedToPng() throws {
        let tiff = NSBitmapImageRep(data: pngData())!.tiffRepresentation!
        pasteboard.setData(tiff, forType: .tiff)
        let images = try ImageInsertion.images(from: pasteboard, note: note, libraryRoot: root, now: fixedDate)
        let saved = root.appendingPathComponent("Notes/\(images[0].link)")
        let header = try Data(contentsOf: saved).prefix(4)
        XCTAssertEqual(Array(header), [0x89, 0x50, 0x4E, 0x47], "PNG signature")
    }

    func testFileOutsideLibraryIsCopied() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString) photo.JPG")
        try pngData().write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        pasteboard.writeObjects([outside as NSURL])
        let images = try ImageInsertion.images(from: pasteboard, note: note, libraryRoot: root, now: fixedDate)
        XCTAssertEqual(images.count, 1)
        XCTAssertTrue(images[0].link.hasPrefix("assets/My-Trip-"))
        XCTAssertTrue(images[0].link.hasSuffix(".jpg"))
        XCTAssertTrue(images[0].alt.hasSuffix(" photo"))
    }

    func testFileInsideLibraryIsLinkedNotCopied() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Media"), withIntermediateDirectories: true)
        let inside = root.appendingPathComponent("Media/chart (v2).png")
        try pngData().write(to: inside)
        pasteboard.writeObjects([inside as NSURL])
        let images = try ImageInsertion.images(from: pasteboard, note: note, libraryRoot: root)
        XCTAssertEqual(images, [ImageInsertion.Image(alt: "chart (v2)", link: "../Media/chart%20%28v2%29.png")])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/assets").path))
    }

    func testTextAndOtherFilesAreLeftToTheDefaultPaste() throws {
        pasteboard.setString("just text", forType: .string)
        XCTAssertFalse(ImageInsertion.containsImages(pasteboard))

        pasteboard.clearContents()
        let pdf = root.appendingPathComponent("doc.pdf")
        try Data("x".utf8).write(to: pdf)
        pasteboard.writeObjects([pdf as NSURL])
        XCTAssertFalse(ImageInsertion.containsImages(pasteboard))
    }

    func testRichTextWithPictureStaysText() {
        pasteboard.declareTypes([.string, .png], owner: nil)
        pasteboard.setString("Some paragraph", forType: .string)
        pasteboard.setData(pngData(), forType: .png)
        XCTAssertFalse(ImageInsertion.containsImages(pasteboard))
    }

    func testMarkdownStandsOnItsOwnLine() {
        let images = [ImageInsertion.Image(alt: "a [b]", link: "x.png"), .init(alt: "", link: "y.png")]
        let text = "before after" as NSString
        XCTAssertEqual(ImageInsertion.markdown(images, in: text, replacing: NSRange(location: 6, length: 1)),
                       "\n![a \\[b\\]](x.png)\n![](y.png)\n")
        // Empty line: the existing newline already ends it.
        XCTAssertEqual(ImageInsertion.markdown([images[1]], in: "a\n\nb" as NSString, replacing: NSRange(location: 2, length: 0)),
                       "![](y.png)")
    }

    func testPasteInTextViewInsertsUndoableMarkdown() {
        let view = MarkdownTextView(usingTextLayoutManager: true)
        view.string = "Intro\n"
        view.noteURL = { [note] in note }
        view.libraryRoot = root
        pasteboard.setData(pngData(), forType: .png)
        XCTAssertTrue(view.insertImages(from: pasteboard, replacing: NSRange(location: 6, length: 0)))
        XCTAssertTrue(view.string.hasPrefix("Intro\n![](assets/My-Trip-"))
        XCTAssertTrue(view.string.hasSuffix(".png)"))
        XCTAssertEqual(view.selectedRange().location, (view.string as NSString).length)

        pasteboard.clearContents()
        pasteboard.setString("text", forType: .string)
        XCTAssertFalse(view.insertImages(from: pasteboard, replacing: NSRange(location: 0, length: 0)), "text falls through")
    }
}
