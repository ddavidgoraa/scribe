import AppKit
import WebKit
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
        XCTAssertNil(HelpDocument(fileName: "README.md"))
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

final class HelpLinkPolicyTests: XCTestCase {
    func testOnlyWebAndMailLinksLeaveTheHelpWindow() {
        XCTAssertTrue(HelpContent.isExternalLinkAllowed(URL(string: "https://github.com")!))
        XCTAssertTrue(HelpContent.isExternalLinkAllowed(URL(string: "HTTP://example.com")!))
        XCTAssertTrue(HelpContent.isExternalLinkAllowed(URL(string: "mailto:someone@example.com")!))
        XCTAssertFalse(HelpContent.isExternalLinkAllowed(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(HelpContent.isExternalLinkAllowed(URL(string: "x-apple.systempreferences:com.apple")!))
        XCTAssertFalse(HelpContent.isExternalLinkAllowed(URL(string: "javascript:alert(1)")!))
    }
}

/// The Help window renders inside the App Sandbox and cannot fetch anything from the web.
@MainActor
final class HelpWebViewTests: XCTestCase {
    private func load(_ html: String, into web: WKWebView) async throws {
        web.loadHTMLString(html, baseURL: HelpContent.baseURL.appendingPathComponent("GETTING-STARTED.md"))
        try await Task.sleep(for: .milliseconds(300))
        for _ in 0..<50 where web.isLoading { try await Task.sleep(for: .milliseconds(100)) }
    }

    func testGuideRendersWithItsImages() async throws {
        let web = HelpWebSecurity.makeWebView()
        await HelpWebSecurity.applyOfflineRules(to: web)
        try await load(HelpContent.html(for: .gettingStarted)!, into: web)
        let title = try await web.evaluateJavaScript("document.querySelector('h1').textContent") as? String
        let images = try await web.evaluateJavaScript("Array.from(document.images).filter(i => i.naturalWidth > 0).length") as? Int
        XCTAssertEqual(title, "Getting started with Scribe")
        XCTAssertEqual(images, 6, "embedded screenshots load")
    }

    func testWebRequestsAreBlocked() async throws {
        let web = HelpWebSecurity.makeWebView()
        await HelpWebSecurity.applyOfflineRules(to: web)
        try await load(#"<img id="remote" src="https://www.apple.com/favicon.ico">"#, into: web)
        try await Task.sleep(for: .seconds(1))
        let width = try await web.evaluateJavaScript("document.getElementById('remote').naturalWidth") as? Int
        XCTAssertEqual(width, 0, "remote image must not load")
    }
}
