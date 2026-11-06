import MdCore
import XCTest
@testable import Scribe

@MainActor
final class NoteDocumentTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        UserDefaults.standard.removeObject(forKey: UserDefaults.autoNameKey)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeNote(_ name: String, _ contents: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func disk(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    func testAutosavesAfterDelay() async throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        doc.text = "two"
        XCTAssertEqual(try disk(url), "one")
        try await Task.sleep(for: .milliseconds(1300))
        XCTAssertEqual(try disk(url), "two")
        XCTAssertFalse(doc.isDirty)
    }

    func testOwnSaveIsNotSeenAsExternalChange() throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        doc.text = "two"
        doc.save()
        XCTAssertFalse(doc.checkDisk())
        XCTAssertNil(doc.conflict)
        XCTAssertEqual(doc.reloadGeneration, 0)
    }

    func testCleanNoteReloadsFromDisk() throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        doc.checkDisk()
        XCTAssertEqual(doc.text, "theirs")
        XCTAssertEqual(doc.reloadGeneration, 1)
        XCTAssertFalse(doc.isDirty)
    }

    func testConflictPausesAutosaveUntilResolved() throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        doc.text = "mine"
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        doc.checkDisk()
        XCTAssertEqual(doc.conflict, .modifiedOnDisk("theirs"))
        doc.save()
        XCTAssertEqual(try disk(url), "theirs", "must not overwrite during a conflict")

        doc.keepMine()
        XCTAssertNil(doc.conflict)
        XCTAssertEqual(try disk(url), "mine")
    }

    func testReloadResolvesConflict() throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        doc.text = "mine"
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        doc.checkDisk()
        doc.reloadFromDisk()
        XCTAssertNil(doc.conflict)
        XCTAssertEqual(doc.text, "theirs")
        XCTAssertFalse(doc.isDirty)
    }

    func testDeletion() throws {
        let url = try makeNote("a.md", "one")
        let doc = try NoteDocument(url: url)
        try FileManager.default.removeItem(at: url)
        XCTAssertTrue(doc.checkDisk(), "clean note closes")

        let url2 = try makeNote("b.md", "one")
        let dirty = try NoteDocument(url: url2)
        dirty.text = "mine"
        try FileManager.default.removeItem(at: url2)
        XCTAssertFalse(dirty.checkDisk())
        XCTAssertEqual(dirty.conflict, .deletedOnDisk)
        dirty.keepMine()
        XCTAssertEqual(try disk(url2), "mine", "recreated")
    }

    func testNewNoteFollowsFirstLineUntilManualRename() throws {
        let url = URL(fileURLWithPath: try createUntitledNote(dir: dir.path))
        let doc = try NoteDocument(url: url)
        var renamedTo: URL?
        doc.onRename = { renamedTo = $0 }

        doc.text = "# Shopping list\n- milk"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Shopping list.md")
        XCTAssertEqual(renamedTo, doc.url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try disk(doc.url), "# Shopping list\n- milk")

        try doc.rename(to: "Groceries")
        doc.text = "# Something else"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Groceries.md")
    }

    func testUntitledNoteRenamesAfterReopen() throws {
        // Simulates an app restart: a fresh document, no in-memory state.
        let url = try makeNote("Untitled 2.md", "draft")
        let doc = try NoteDocument(url: url)
        doc.text = "# Trip to Kraków"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Trip to Kraków.md")
    }

    func testAutoNamedNoteKeepsFollowingAfterReopen() throws {
        let url = try makeNote("Trip.md", "# Trip\nbody")
        let doc = try NoteDocument(url: url)
        doc.text = "# Trip to Kraków\nbody"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Trip to Kraków.md")
        doc.text = "# Trip to Gdańsk\nbody"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Trip to Gdańsk.md")
    }

    func testManuallyNamedNoteDoesNotFollowAfterReopen() throws {
        let url = try makeNote("Travel.md", "# Trip\nbody")
        let doc = try NoteDocument(url: url)
        doc.text = "# Trip to Kraków\nbody"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Travel.md")
    }

    func testAutoNamingCanBeDisabled() throws {
        UserDefaults.standard.set(false, forKey: UserDefaults.autoNameKey)
        defer { UserDefaults.standard.removeObject(forKey: UserDefaults.autoNameKey) }
        let doc = try NoteDocument(url: URL(fileURLWithPath: try createUntitledNote(dir: dir.path)))
        doc.text = "Title"
        doc.save()
        XCTAssertEqual(doc.url.lastPathComponent, "Untitled.md")
    }
}
