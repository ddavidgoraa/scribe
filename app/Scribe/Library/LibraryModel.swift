import AppKit
import MdCore
import Observation

/// The open library folder, its tree, and the currently open note.
@MainActor
@Observable
final class LibraryModel {
    private static let rootKey = "libraryPath"
    private static let sortKey = "librarySort"

    private(set) var root: URL?
    private(set) var nodes: [LibraryNode] = []
    private(set) var document: NoteDocument?
    /// Sidebar selection (relative path).
    var selection: String? {
        didSet { if selection != oldValue { open(relativePath: selection) } }
    }
    var sort: LibrarySort {
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: Self.sortKey)
            refresh()
        }
    }
    var errorMessage: String?

    private var watcher: LibraryWatcher?

    init() {
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(LibrarySort.init) ?? .name
        if let path = UserDefaults.standard.string(forKey: Self.rootKey),
           FileManager.default.fileExists(atPath: path) {
            openLibrary(at: URL(fileURLWithPath: path))
        }
    }

    // MARK: Library

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = String(localized: "Open Library")
        panel.message = String(localized: "Choose the folder that holds your notes.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openLibrary(at: url)
    }

    func openLibrary(at url: URL) {
        closeDocument()
        watcher?.stop()
        let resolved = url.resolvingSymlinksInPath()
        root = resolved
        UserDefaults.standard.set(resolved.path, forKey: Self.rootKey)
        refresh()
        do {
            watcher = try LibraryWatcher(root: resolved.path, listener: WatchListener { [weak self] _ in
                Task { @MainActor in self?.handleExternalChanges() }
            })
        } catch {
            report(error)
        }
    }

    func refresh() {
        guard let root else { return }
        do {
            nodes = LibraryTree.build(try scanLibrary(root: root.path), sort: sort)
        } catch {
            report(error)
        }
    }

    private func handleExternalChanges() {
        refresh()
        if let document, document.checkDisk() {
            closeDocument()
        }
    }

    // MARK: Notes

    func url(for relativePath: String) -> URL? {
        root?.appendingPathComponent(relativePath)
    }

    func relativePath(of url: URL) -> String? {
        guard let root else { return nil }
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard url.path.hasPrefix(rootPath) else { return nil }
        return String(url.path.dropFirst(rootPath.count))
    }

    private func open(relativePath: String?) {
        guard let relativePath else { closeDocument(); return }
        if let document, self.relativePath(of: document.url) == relativePath { return }
        guard let url = url(for: relativePath) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue
        else { return } // folders just expand
        closeDocument(keepSelection: true)
        do {
            let doc = try NoteDocument(url: url)
            doc.onRename = { [weak self] newURL in self?.documentRenamed(to: newURL) }
            doc.onError = { [weak self] error in self?.report(error) }
            document = doc
        } catch {
            report(error)
        }
    }

    private func closeDocument(keepSelection: Bool = false) {
        document?.save()
        document = nil
        if !keepSelection { selection = nil }
    }

    /// Saves pending edits (app quit, deactivate).
    func flush() {
        document?.save()
    }

    /// Creates `Untitled.md` in `folder` (relative path; `nil` = folder of the open note, else root).
    func newNote(in folder: String? = nil) {
        guard let root else { return }
        let dir: URL
        if let folder {
            dir = folder.isEmpty ? root : root.appendingPathComponent(folder)
        } else if let document {
            dir = document.url.deletingLastPathComponent()
        } else {
            dir = root
        }
        do {
            let path = try createUntitledNote(dir: dir.path)
            refresh()
            selection = relativePath(of: URL(fileURLWithPath: path))
        } catch {
            report(error)
        }
    }

    func rename(_ relativePath: String, to name: String) {
        if let document, self.relativePath(of: document.url) == relativePath {
            do {
                try document.rename(to: name)
                documentRenamed(to: document.url)
            } catch {
                report(error)
            }
            return
        }
        guard let url = url(for: relativePath) else { return }
        do {
            _ = try renameNote(path: url.path, newName: name)
            refresh()
        } catch {
            report(error)
        }
    }

    private func documentRenamed(to url: URL) {
        refresh()
        selection = relativePath(of: url)
    }

    func revealInFinder(_ relativePath: String) {
        guard let url = url(for: relativePath) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

/// Bridges Rust watcher callbacks (background thread) to a Swift closure.
private final class WatchListener: LibraryListener {
    private let handler: @Sendable ([String]) -> Void
    init(_ handler: @escaping @Sendable ([String]) -> Void) { self.handler = handler }
    func onChanges(paths: [String]) { handler(paths) }
}
