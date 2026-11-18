import AppKit
import PDFKit
import XCTest
@testable import Scribe

@MainActor
final class PrintingTests: XCTestCase {
    private let note = #"""
    # Trip to Kraków

    The train left right on time. Fog outside — the perfect moment to **finish the draft** and stop *fiddling with commas*. Einstein was right: $E = mc^2$.

    $$
    \int_0^1 x^2\,dx = \frac{1}{3}
    $$

    ## To do

    - [ ] Book a hotel
    - [x] Buy tickets
    - Pack light

    1. Morning train
    2. Old town

    > Travel is the only thing you buy that makes you richer.

    ---

    ```swift
    let trip = Trip(to: "Kraków")
    ```

    """#

    /// With SCRIBE_PRINT_SNAPSHOTS=1, also saves each printed page as PNG (visual check)
    /// in the app's temporary directory (the sandbox allows writing there).
    private var snapshotDirectory: String? {
        guard ProcessInfo.processInfo.environment["SCRIBE_PRINT_SNAPSHOTS"] == "1" else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("print-snapshots")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        print("print snapshots:", dir.path)
        return dir.path
    }

    /// Prints the note the way "Save as PDF" in the print panel does: a normal print
    /// operation (pagination, header and footer) whose output is a PDF file.
    private func printToPDF(_ text: String) throws -> PDFDocument {
        let info = NotePrinter.printInfo()
        info.paperSize = NSSize(width: 595, height: 842) // A4
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("print-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let view = NotePrinter.makeView(text: text, title: "Trip to Kraków", baseURL: nil, font: .sans, printInfo: info)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        XCTAssertTrue(operation.run())
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        return pdf
    }

    private func text(of pdf: PDFDocument) -> [String] {
        (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }
    }

    func testPrintIsACleanDocument() throws {
        let pdf = try printToPDF(note)
        let printed = text(of: pdf).joined(separator: "\n")
        XCTAssertTrue(printed.contains("Trip to Kraków"))
        XCTAssertTrue(printed.contains("finish the draft"))
        for syntax in ["**", "$$", "[ ]", "[x]", "## ", "---", "```", "> Travel"] {
            XCTAssertFalse(printed.contains(syntax), "Markdown syntax \(syntax) printed")
        }
        XCTAssertTrue(printed.contains("1. Morning train"), "numbered lists keep their numbers")
        // (PDF text extraction collapses runs of spaces.)
        let collapsed = printed.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        XCTAssertTrue(collapsed.contains("Trip to Kraków · 1"), "footer with title and page number")

        if let directory = snapshotDirectory {
            for i in 0..<pdf.pageCount {
                let image = pdf.page(at: i)!.thumbnail(of: NSSize(width: 1190, height: 1684), for: .mediaBox)
                try NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
                    .write(to: URL(fileURLWithPath: directory).appendingPathComponent("page-\(i + 1).png"))
            }
        }
    }

    /// The App Sandbox blocks printing (the print panel, printers) without this entitlement;
    /// printing to a PDF file in the tests above works even without it.
    func testTheSandboxAllowsPrinting() throws {
        let task = try XCTUnwrap(SecTaskCreateFromSelf(nil))
        let sandboxed = SecTaskCopyValueForEntitlement(task, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
        let print = SecTaskCopyValueForEntitlement(task, "com.apple.security.print" as CFString, nil) as? Bool
        XCTAssertEqual(sandboxed, true)
        XCTAssertEqual(print, true, "com.apple.security.print missing from Scribe.entitlements")
    }

    func testLongNotesSpanSeveralPagesWithoutCuttingLines() throws {
        let long = (1...120).map { "Paragraph \($0): the quick brown fox jumps over the lazy dog, again and again." }
            .joined(separator: "\n\n")
        let pdf = try printToPDF(long)
        XCTAssertGreaterThan(pdf.pageCount, 2)
        let pages = text(of: pdf)
        for n in [1, 40, 80, 120] {
            XCTAssertTrue(pages.contains { $0.contains("Paragraph \(n): the quick brown fox") }, "paragraph \(n) whole on one page")
        }
        XCTAssertTrue(pages.last?.contains("\(pdf.pageCount) / \(pdf.pageCount)") ?? false, "page x / total in the footer")
    }
}
