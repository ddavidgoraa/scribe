import MdCore
import XCTest
@testable import Scribe

final class LibraryTreeTests: XCTestCase {
    private func entry(_ path: String, dir: Bool = false, ms: Int64 = 0) -> LibraryEntry {
        LibraryEntry(relativePath: path, isDir: dir, modifiedMs: ms)
    }

    private let entries: [LibraryEntry] = [
        LibraryEntry(relativePath: "b.md", isDir: false, modifiedMs: 100),
        LibraryEntry(relativePath: "Note 10.md", isDir: false, modifiedMs: 300),
        LibraryEntry(relativePath: "Note 2.md", isDir: false, modifiedMs: 200),
        LibraryEntry(relativePath: "Zeta", isDir: true, modifiedMs: 0),
        LibraryEntry(relativePath: "Zeta/inner.md", isDir: false, modifiedMs: 0),
        LibraryEntry(relativePath: "Alpha", isDir: true, modifiedMs: 999),
    ]

    func testFoldersFirstThenNaturalNameOrder() {
        let tree = LibraryTree.build(entries, sort: .name)
        XCTAssertEqual(tree.map(\.id), ["Alpha", "Zeta", "b.md", "Note 2.md", "Note 10.md"])
        XCTAssertEqual(tree[0].children, [])
        XCTAssertEqual(tree[1].children?.map(\.id), ["Zeta/inner.md"])
        XCTAssertNil(tree[2].children)
    }

    func testModifiedSortNewestFirstFoldersStillByName() {
        let tree = LibraryTree.build(entries, sort: .modified)
        XCTAssertEqual(tree.map(\.id), ["Alpha", "Zeta", "Note 10.md", "Note 2.md", "b.md"])
    }

    func testDisplayNameDropsExtensionForNotesOnly() {
        let tree = LibraryTree.build([entry("a.b", dir: true), entry("Plan.md")], sort: .name)
        XCTAssertEqual(tree.map(\.displayName), ["a.b", "Plan"])
    }
}
