import XCTest
@testable import Scribe

/// Write access to the library folder (App Sandbox).
@MainActor
final class LibraryAccessTests: XCTestCase {
    private let keys = ["libraryPath", "libraryBookmark", "lastNotePath"]
    private var saved: [String: Any] = [:]
    private var folders: [URL] = []

    override func setUp() async throws {
        for key in keys { saved[key] = UserDefaults.standard.object(forKey: key) }
    }

    override func tearDown() async throws {
        for key in keys {
            if let value = saved[key] { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for folder in folders {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private func makeFolder(writable: Bool) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try "# Hello\n".write(to: url.appendingPathComponent("Hello.md"), atomically: true, encoding: .utf8)
        if !writable { try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: url.path) }
        folders.append(url)
        return url
    }

    func testAWritableLibraryCreatesNotesAndIsRemembered() throws {
        UserDefaults.standard.removeObject(forKey: "libraryBookmark")
        let model = LibraryModel()
        model.openLibrary(at: try makeFolder(writable: true))
        XCTAssertFalse(model.needsWriteAccess)
        XCTAssertNotNil(UserDefaults.standard.data(forKey: "libraryBookmark"))
        model.newNote()
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.document?.url.lastPathComponent, "Untitled.md")
    }

    func testReadOnlyAccessAsksForTheFolderAgainAndIsNotRemembered() throws {
        UserDefaults.standard.removeObject(forKey: "libraryBookmark")
        let model = LibraryModel()
        model.openLibrary(at: try makeFolder(writable: false))
        XCTAssertTrue(model.needsWriteAccess, "read-only library must prompt for access")
        XCTAssertNil(UserDefaults.standard.data(forKey: "libraryBookmark"), "read-only access must not be saved")
        XCTAssertEqual(model.noteCount, 1, "the notes can still be read")
    }

    func testAPlainPathFromBeforeTheSandboxIsNotUsed() throws {
        UserDefaults.standard.removeObject(forKey: "libraryBookmark")
        UserDefaults.standard.set(try makeFolder(writable: true).path, forKey: "libraryPath")
        XCTAssertNil(LibraryModel().root, "without a bookmark, the user chooses the folder")
    }
}
