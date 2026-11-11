import AppKit
import MdCore
import Observation
import SwiftUI
import WebKit

/// The user guides bundled from `docs/`, shown in the Help window.
enum HelpDocument: String, CaseIterable, Identifiable {
    case gettingStarted = "GETTING-STARTED"
    case manual = "MANUAL"

    var id: Self { self }
    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .manual: "Manual"
        }
    }

    init?(fileName: String) {
        self.init(rawValue: (fileName as NSString).deletingPathExtension)
    }
}

/// Which guide the Help window shows (shared by menus and buttons).
@MainActor
@Observable
final class HelpModel {
    var document: HelpDocument = .gettingStarted
    /// Heading to scroll to after loading (a link like `MANUAL.md#5-math`).
    var anchor: String?
}

enum HelpContent {
    /// Pretend origin for the guides, so relative links can be told apart from the web.
    static let baseURL = URL(string: "https://help.scribe.invalid/")!

    static var docsDirectory: URL? {
        Bundle.main.url(forResource: "docs", withExtension: nil)
    }

    /// A complete HTML page for `document`, with images embedded as data URLs.
    static func html(for document: HelpDocument) -> String? {
        guard let dir = docsDirectory,
              let markdown = try? String(contentsOf: dir.appendingPathComponent("\(document.rawValue).md"), encoding: .utf8)
        else { return nil }
        let body = inlineImages(in: markdownToHtml(markdown: markdown), from: dir)
        return template.replacingOccurrences(of: "{{title}}", with: document.title)
            .replacingOccurrences(of: "{{body}}", with: body)
    }

    /// Replaces `src="images/x.png"` with the image's data so the page needs no file access.
    static func inlineImages(in html: String, from dir: URL) -> String {
        var result = html
        let pattern = try! NSRegularExpression(pattern: #"src="([^":]+\.(png|jpe?g|gif))""#, options: .caseInsensitive)
        let matches = pattern.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()
        for match in matches {
            guard let pathRange = Range(match.range(at: 1), in: html),
                  let whole = Range(match.range, in: result) else { continue }
            let path = String(html[pathRange])
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(path)) else { continue }
            let ext = (path as NSString).pathExtension.lowercased()
            let mime = ext == "png" ? "image/png" : ext == "gif" ? "image/gif" : "image/jpeg"
            result.replaceSubrange(whole, with: "src=\"data:\(mime);base64,\(data.base64EncodedString())\"")
        }
        return result
    }

    private static let template = """
    <!doctype html><html><head><meta charset="utf-8"><title>{{title}}</title>
    <meta name="color-scheme" content="light dark">
    <style>
    :root { --paper:#fff; --paper2:#F5F5F7; --ink:#1D1D1F; --ink2:#6E6E73; --ink3:#AEAEB2; --line:#E5E5EA; --accent:#1A9FFF; }
    @media (prefers-color-scheme: dark) {
      :root { --paper:#161617; --paper2:#1F1F21; --ink:#EDEDED; --ink2:#98989D; --ink3:#636366; --line:#2C2C2E; --accent:#3BAFFF; }
    }
    html { background: var(--paper); }
    body { font: 15px/1.6 -apple-system, "SF Pro Text", sans-serif; color: var(--ink); max-width: 760px;
           margin: 0 auto; padding: 36px 40px 80px; -webkit-font-smoothing: antialiased; }
    h1 { font-size: 30px; line-height: 1.2; letter-spacing: -0.01em; margin: 8px 0 12px; }
    h2 { font-size: 21px; margin: 40px 0 10px; }
    h3 { font-size: 16px; margin: 26px 0 6px; }
    p, li { color: var(--ink); }
    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    hr { border: none; border-top: 1px solid var(--line); margin: 32px 0; }
    code { font: 13px "SF Mono", Menlo, monospace; background: var(--paper2); padding: 1px 5px; border-radius: 5px; }
    pre { background: var(--paper2); padding: 12px 16px; border-radius: 10px; overflow-x: auto; }
    pre code { background: none; padding: 0; }
    blockquote { margin: 16px 0; padding: 10px 16px; border-left: 3px solid var(--accent);
                 background: var(--paper2); border-radius: 0 10px 10px 0; color: var(--ink2); }
    blockquote p { margin: 0; color: var(--ink2); }
    table { border-collapse: collapse; width: 100%; margin: 14px 0; font-size: 14px; }
    th, td { text-align: left; padding: 8px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
    th { font-size: 12px; text-transform: uppercase; letter-spacing: .05em; color: var(--ink3); }
    img { max-width: 100%; border-radius: 12px; border: 1px solid var(--line);
          box-shadow: 0 10px 30px rgba(0,0,0,.08); margin: 8px 0; }
    strong { font-weight: 650; }
    </style></head><body>{{body}}
    <script>
    // GitHub-style heading ids so in-document links (#1-installation) work.
    document.querySelectorAll('h1,h2,h3,h4').forEach(h => {
      if (!h.id) h.id = h.textContent.trim().toLowerCase().replace(/[^\\p{L}\\p{N}\\s-]/gu, '').replace(/\\s/g, '-');
    });
    function scribeScrollTo(id) { const el = document.getElementById(id); if (el) el.scrollIntoView(); }
    </script></body></html>
    """
}

/// The Help window: the guide on the left of a segmented control in the toolbar.
struct HelpView: View {
    @Environment(HelpModel.self) private var help

    var body: some View {
        @Bindable var help = help
        HelpWebView(document: help.document, anchor: help.anchor) { document, anchor in
            help.anchor = anchor
            help.document = document
        }
        .frame(minWidth: 620, minHeight: 480)
        .navigationTitle(help.document.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Guide", selection: $help.document) {
                    ForEach(HelpDocument.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }
}

private struct HelpWebView: NSViewRepresentable {
    let document: HelpDocument
    let anchor: String?
    let navigate: (HelpDocument, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.navigationDelegate = context.coordinator
        web.setValue(false, forKey: "drawsBackground")
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.navigate = navigate
        if coordinator.loaded != document {
            coordinator.loaded = document
            coordinator.pendingAnchor = anchor
            let html = HelpContent.html(for: document) ?? "<p>This guide is missing from the app.</p>"
            web.loadHTMLString(html, baseURL: HelpContent.baseURL.appendingPathComponent("\(document.rawValue).md"))
        } else if let anchor {
            coordinator.scroll(web, to: anchor)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: HelpDocument?
        var pendingAnchor: String?
        var navigate: (HelpDocument, String?) -> Void = { _, _ in }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let anchor = pendingAnchor {
                pendingAnchor = nil
                scroll(webView, to: anchor)
            }
        }

        func scroll(_ web: WKWebView, to anchor: String) {
            let escaped = anchor.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            web.evaluateJavaScript("scribeScrollTo('\(escaped)')")
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url else {
                decisionHandler(.allow)
                return
            }
            // Web links open in the browser.
            guard url.host == HelpContent.baseURL.host else {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            // Links to the other guide switch documents; same-page anchors scroll.
            let file = url.lastPathComponent
            let anchor = url.fragment.flatMap { $0.removingPercentEncoding ?? $0 }
            if let target = HelpDocument(fileName: file) {
                if target == loaded, let anchor {
                    scroll(webView, to: anchor)
                } else {
                    navigate(target, anchor)
                }
            }
            decisionHandler(.cancel)
        }
    }
}
