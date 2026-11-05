import XCTest
@testable import Scribe

final class ExternalChangeTests: XCTestCase {
    func testOwnWriteIsIgnored() {
        XCTAssertEqual(ExternalChange.resolve(disk: "a", synced: "a", current: "a b"), .none)
    }

    func testCleanNoteReloadsSilently() {
        XCTAssertEqual(ExternalChange.resolve(disk: "new", synced: "old", current: "old"), .reload("new"))
    }

    func testDiskMatchingEditorIsAdopted() {
        XCTAssertEqual(ExternalChange.resolve(disk: "same", synced: "old", current: "same"), .reload("same"))
    }

    func testDirtyNoteConflicts() {
        XCTAssertEqual(ExternalChange.resolve(disk: "theirs", synced: "old", current: "mine"), .conflict("theirs"))
    }

    func testDeletion() {
        XCTAssertEqual(ExternalChange.resolve(disk: nil, synced: "a", current: "a"), .deletedClean)
        XCTAssertEqual(ExternalChange.resolve(disk: nil, synced: "a", current: "b"), .deletedDirty)
    }
}
