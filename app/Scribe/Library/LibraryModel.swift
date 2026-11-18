import AppKit
import MdCore
import Observation

/// The open library folder, its tree, and the currently open note.
@MainActor
@Observable
final class LibraryModel {
    /// Plain path of the library, written by versions before the App Sandbox.
    private static let rootKey = "libraryPath"
    /// Security-scoped bookmark of the library folder (keeps access across launches).
    private static let bookmarkKey = "libraryBookmark"
    private static let sortKey = "librarySort"
    private static let lastNoteKey = "lastNotePath"

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
    let search = SearchModel()
    /// UI state. The library panel starts hidden: the window opens on the last note.
    var isSidebarVisible = false
    var isQuickOpenPresented = false
    /// Incremented to focus the panel's search field (⌘⇧F).
    private(set) var searchFocusRequest = 0
    /// Expanded folders in the library tree.
    var expandedFolders: Set<String> = []

    func toggleSidebar() {
        isSidebarVisible.toggle()
    }

    /// ⌘⇧F: show the panel and focus its search field.
    func focusSearch() {
        isSidebarVisible = true
        searchFocusRequest += 1
    }
    /// Range to select in the open note (search results), consumed by the editor.
    private(set) var pendingReveal: RevealRequest?

    private var watcher: LibraryWatcher?

    init() {
        sort = UserDefaults.standard.string(forKey: Self.sortKey).flatMap(LibrarySort.init) ?? .name
        if let url = Self.savedLibraryURL() {
            openLibrary(at: url)
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

    /// The library folder from the last launch: from its security-scoped bookmark, or
    /// from a plain path saved by an older version (readable only outside the sandbox).
    private static func savedLibraryURL() -> URL? {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: bookmarkKey) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url // a stale bookmark is re-saved by openLibrary
            }
        }
        if let path = defaults.string(forKey: rootKey), FileManager.default.isReadableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    /// The folder whose security-scoped access this session holds.
    private var accessedFolder: URL?

    func openLibrary(at url: URL) {
        closeDocument()
        watcher?.stop()
        // App Sandbox: hold access to the folder for this session and remember it for the
        // next one. (Outside the sandbox these calls are harmless no-ops.)
        accessedFolder?.stopAccessingSecurityScopedResource()
        accessedFolder = url.startAccessingSecurityScopedResource() ? url : nil
        if let bookmark = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        }
        let resolved = url.resolvingSymlinksInPath()
        root = resolved
        UserDefaults.standard.set(resolved.path, forKey: Self.rootKey)
        refresh()
        search.open(root: resolved)
        if let last = UserDefaults.standard.string(forKey: Self.lastNoteKey),
           let relative = relativePath(of: URL(fileURLWithPath: last)),
           FileManager.default.fileExists(atPath: last) {
            selection = relative
        }
        // FSEvents setup waits on a background thread; don't block the main thread on it.
        let listener = WatchListener { [weak self] _ in
            Task { @MainActor in self?.handleExternalChanges() }
        }
        let path = resolved.path
        Task {
            let result = await Task.detached(priority: .utility) {
                Result { try LibraryWatcher(root: path, listener: listener) }
            }.value
            guard root == resolved else { return } // another library was opened meanwhile
            switch result {
            case .success(let created): watcher = created
            case .failure(let error): report(error)
            }
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
        search.refresh()
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
        // Compare resolved paths: `/private/tmp/x` and `/tmp/x` are the same file. Resolving
        // only works for existing items, so also resolve the folder and re-append the name.
        let viaParent = url.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(url.lastPathComponent)
        for path in [url.path, url.resolvingSymlinksInPath().path, viaParent.path] where path.hasPrefix(rootPath) {
            return String(path.dropFirst(rootPath.count))
        }
        return nil
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
            UserDefaults.standard.set(url.path, forKey: Self.lastNoteKey)
            expandParents(of: relativePath)
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

    /// File → Print (⌘P): prints the open note as a clean document, wherever the keyboard
    /// focus is (editor, library panel, search). Returns false when no note is open.
    @discardableResult
    func printNote() -> Bool {
        guard let document else { return false }
        let url = document.url
        NotePrinter.print(text: document.text,
                          title: url.deletingPathExtension().lastPathComponent,
                          baseURL: url.deletingLastPathComponent(),
                          font: EditorFont(storedValue: UserDefaults.standard.string(forKey: EditorSettings.fontKey)),
                          window: NSApp.mainWindow ?? NSApp.keyWindow)
        return true
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
        UserDefaults.standard.set(url.path, forKey: Self.lastNoteKey)
    }

    private func expandParents(of relativePath: String) {
        var parent = LibraryTree.parent(of: relativePath)
        while !parent.isEmpty {
            expandedFolders.insert(parent)
            parent = LibraryTree.parent(of: parent)
        }
    }

    /// Notes changed most recently, newest first.
    func recentNotes(limit: Int = 5) -> [LibraryNode] {
        var notes: [LibraryNode] = []
        func walk(_ nodes: [LibraryNode]) {
            for node in nodes {
                if let children = node.children { walk(children) } else { notes.append(node) }
            }
        }
        walk(nodes)
        return Array(notes.sorted { $0.modified > $1.modified }.prefix(limit))
    }

    var noteCount: Int { notePaths.count }

    /// Quick Open ⌘⏎: a new note whose first line is `title` (named after it on save).
    func newNote(titled title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        newNote()
        guard !title.isEmpty, let document else { return }
        document.text = "# \(title)\n\n"
        document.save()
        pendingReveal = RevealRequest(relativePath: relativePath(of: document.url) ?? "",
                                      range: NSRange(location: (document.text as NSString).length, length: 0))
    }

    /// All notes (relative paths), for quick open.
    var notePaths: [String] {
        var paths: [String] = []
        func walk(_ nodes: [LibraryNode]) {
            for node in nodes {
                if let children = node.children { walk(children) } else { paths.append(node.id) }
            }
        }
        walk(nodes)
        return paths
    }

    /// Opens a note and selects `range` in it (a search result).
    func open(_ relativePath: String, revealing range: NSRange? = nil) {
        selection = relativePath
        if let range { pendingReveal = RevealRequest(relativePath: relativePath, range: range) }
    }

    func revealHandled(_ request: RevealRequest) {
        if pendingReveal == request { pendingReveal = nil }
    }

    func revealInFinder(_ relativePath: String) {
        guard let url = url(for: relativePath) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}

struct RevealRequest: Equatable {
    let id = UUID()
    let relativePath: String
    let range: NSRange
}

/// Bridges Rust watcher callbacks (background thread) to a Swift closure.
private final class WatchListener: LibraryListener {
    private let handler: @Sendable ([String]) -> Void
    init(_ handler: @escaping @Sendable ([String]) -> Void) { self.handler = handler }
    func onChanges(paths: [String]) { handler(paths) }
}
