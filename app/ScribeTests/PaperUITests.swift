import AppKit
import XCTest
@testable import Scribe

final class ShortDateTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private let locale = Locale(identifier: "en_US")
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 15))! }

    private func string(_ components: DateComponents) -> String {
        // Time formats use a narrow no-break space before AM/PM.
        ShortDate.string(for: calendar.date(from: components)!, now: now, calendar: calendar, locale: locale)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    func testFormats() {
        XCTAssertEqual(string(DateComponents(year: 2026, month: 11, day: 11, hour: 9, minute: 5)), "9:05 AM")
        XCTAssertEqual(string(DateComponents(year: 2026, month: 11, day: 10, hour: 9)), "Yesterday")
        XCTAssertEqual(string(DateComponents(year: 2026, month: 11, day: 8, hour: 9)), "Sun")
        XCTAssertEqual(string(DateComponents(year: 2026, month: 10, day: 3)), "Oct 3")
        XCTAssertEqual(string(DateComponents(year: 2025, month: 10, day: 3)), "Oct 3, 2025")
    }
}

final class PaletteTests: XCTestCase {
    func testColorsAdaptToAppearance() {
        func resolved(_ color: NSColor, _ name: NSAppearance.Name) -> NSColor {
            var out = color
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance { out = color.usingColorSpace(.sRGB)! }
            return out
        }
        XCTAssertEqual(resolved(Palette.paper, .aqua).redComponent, 1, accuracy: 0.001)
        XCTAssertLessThan(resolved(Palette.paper, .darkAqua).redComponent, 0.1)
        XCTAssertGreaterThan(resolved(Palette.ink, .darkAqua).redComponent, 0.9)
    }
}

@MainActor
final class LibraryModelPaperTests: XCTestCase {
    private var dir: URL!
    private var saved: [String: Any] = [:]
    private let keys = ["libraryPath", "lastNotePath", "librarySort"]

    override func setUp() async throws {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Work"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        try? FileManager.default.removeItem(at: dir)
    }

    private func write(_ path: String, _ text: String, ageDays: Double) throws {
        let url = dir.appendingPathComponent(path)
        try text.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-ageDays * 86_400)], ofItemAtPath: url.path)
    }

    func testRecentNotesAndReopeningTheLastNote() throws {
        try write("Old.md", "old", ageDays: 30)
        try write("Work/Plan.md", "plan", ageDays: 1)
        try write("Fresh.md", "fresh", ageDays: 0)

        let model = LibraryModel()
        model.openLibrary(at: dir)
        XCTAssertFalse(model.isSidebarVisible, "the library starts hidden")
        XCTAssertEqual(model.recentNotes(limit: 2).map(\.id), ["Fresh.md", "Work/Plan.md"])

        model.open("Work/Plan.md")
        XCTAssertTrue(model.expandedFolders.contains("Work"), "parents of the open note are expanded")

        let reopened = LibraryModel()
        reopened.openLibrary(at: dir)
        XCTAssertEqual(reopened.document?.url.lastPathComponent, "Plan.md", "last note reopens")
    }

    func testRelativePathsMatchThroughSymlinks() throws {
        // /tmp is a symlink to /private/tmp.
        let name = "scribe-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: "/private/tmp/\(name)", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: "/private/tmp/\(name)") }
        let model = LibraryModel()
        model.openLibrary(at: URL(fileURLWithPath: "/private/tmp/\(name)"))
        XCTAssertEqual(model.relativePath(of: URL(fileURLWithPath: "/private/tmp/\(name)/a.md")), "a.md")
        XCTAssertEqual(model.relativePath(of: URL(fileURLWithPath: "/tmp/\(name)/a.md")), "a.md")
    }

    func testNewNoteTitledFromQuickOpen() throws {
        let model = LibraryModel()
        model.openLibrary(at: dir)
        model.newNote(titled: "  Meeting notes ")
        XCTAssertEqual(model.document?.url.lastPathComponent, "Meeting notes.md")
        XCTAssertEqual(model.document?.text, "# Meeting notes\n\n")
    }

    func testFocusSearchShowsThePanel() {
        let model = LibraryModel()
        model.focusSearch()
        XCTAssertTrue(model.isSidebarVisible)
        XCTAssertEqual(model.searchFocusRequest, 1)
    }
}
