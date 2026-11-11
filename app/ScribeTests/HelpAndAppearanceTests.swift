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

@MainActor
final class WindowHookTests: XCTestCase {
    func testSecondaryWindowsJoinFullScreenSpaces() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        var configured = false
        let hook = WindowHook.HookView()
        hook.configure = { $0.showsOverFullScreen(); configured = true }
        window.contentView = NSView()
        window.contentView!.addSubview(hook) // configures before the window is shown
        XCTAssertTrue(configured)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(window.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertFalse(window.isVisible)
    }
}
