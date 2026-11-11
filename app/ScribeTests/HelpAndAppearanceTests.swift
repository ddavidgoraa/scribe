import AppKit
import XCTest
@testable import Scribe

@MainActor
final class HelpAndAppearanceTests: XCTestCase {
    func testGuidesAreBundledAndRendered() throws {
        for document in HelpDocument.allCases {
            let html = try XCTUnwrap(HelpContent.html(for: document), "\(document) missing from the bundle")
            XCTAssertTrue(html.contains("<h1>"))
            XCTAssertFalse(html.contains("src=\"images/"), "images are embedded")
        }
        let guide = HelpContent.html(for: .gettingStarted)!
        XCTAssertTrue(guide.contains("src=\"data:image/png;base64,"))
        XCTAssertTrue(guide.contains("href=\"MANUAL.md\""), "cross-links stay relative for the Help window")
    }

    func testDocumentFromLink() {
        XCTAssertEqual(HelpDocument(fileName: "MANUAL.md"), .manual)
        XCTAssertEqual(HelpDocument(fileName: "GETTING-STARTED.md"), .gettingStarted)
        XCTAssertNil(HelpDocument(fileName: "PLAN.md"))
    }

    func testAppearanceSetting() {
        let saved = UserDefaults.standard.object(forKey: AppAppearance.key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: AppAppearance.key) } else { UserDefaults.standard.removeObject(forKey: AppAppearance.key) }
            AppAppearance.current.apply()
        }
        UserDefaults.standard.set("dark", forKey: AppAppearance.key)
        AppAppearance.current.apply()
        XCTAssertEqual(NSApp.appearance?.name, .darkAqua)
        UserDefaults.standard.set("light", forKey: AppAppearance.key)
        AppAppearance.current.apply()
        XCTAssertEqual(NSApp.appearance?.name, .aqua)
        UserDefaults.standard.removeObject(forKey: AppAppearance.key)
        XCTAssertEqual(AppAppearance.current, .system)
        AppAppearance.current.apply()
        XCTAssertNil(NSApp.appearance, "follows macOS")
    }
}
