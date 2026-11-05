import Foundation
import MdCore
import Observation

/// An open note. The editor text is the file's content verbatim; saving is automatic.
@MainActor
@Observable
final class NoteDocument {
    enum Conflict: Equatable {
        /// Changed on disk while we had unsaved edits.
        case modifiedOnDisk(String)
        /// Deleted on disk while we had unsaved edits.
        case deletedOnDisk
    }

    static let autosaveDelay: Duration = .seconds(1)

    private(set) var url: URL
    /// Text in the editor. Setting it schedules an autosave.
    var text: String {
        didSet { if text != oldValue { scheduleSave() } }
    }
    /// Contents we last read from or wrote to disk.
    private(set) var syncedText: String
    private(set) var conflict: Conflict?
    /// Incremented when `text` is replaced from disk, so the editor knows to reload.
    private(set) var reloadGeneration = 0
    /// Created via "New Note" this session and not renamed by hand:
    /// the file name follows the first line.
    var followsFirstLine = false

    /// Called after the file was renamed (auto-naming), with the new URL.
    var onRename: ((URL) -> Void)?
    /// Called when a save or rename fails.
    var onError: ((Error) -> Void)?

    private var saveTask: Task<Void, Never>?

    var isDirty: Bool { text != syncedText }

    init(url: URL) throws {
        let contents = try readNote(path: url.path)
        self.url = url
        self.text = contents
        self.syncedText = contents
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.autosaveDelay)
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// Saves now if there are unsaved edits (or always, with `force`).
    /// Paused while a conflict is unresolved.
    func save(force: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        guard conflict == nil else { return }
        if isDirty || force {
            let snapshot = text
            do {
                try writeNote(path: url.path, contents: snapshot)
                syncedText = snapshot
            } catch {
                onError?(error)
                return
            }
        }
        if followsFirstLine, UserDefaults.standard.autoNameFromFirstLine {
            renameToFirstLine()
        }
    }

    private func renameToFirstLine() {
        guard let title = titleFromText(text: text),
              title != url.deletingPathExtension().lastPathComponent
        else { return }
        do {
            let newPath = try renameNote(path: url.path, newName: title)
            guard newPath != url.path else { return }
            url = URL(fileURLWithPath: newPath)
            onRename?(url)
        } catch {
            onError?(error)
        }
    }

    /// Manual rename: stops following the first line.
    func rename(to name: String) throws {
        save()
        let newPath = try renameNote(path: url.path, newName: name)
        followsFirstLine = false
        url = URL(fileURLWithPath: newPath)
    }

    // MARK: External changes

    /// Compares with the file on disk and reacts. Returns `true` if the note should be closed.
    @discardableResult
    func checkDisk() -> Bool {
        let disk: String? = FileManager.default.fileExists(atPath: url.path)
            ? (try? readNote(path: url.path)) : nil
        switch ExternalChange.resolve(disk: disk, synced: syncedText, current: text) {
        case .none:
            if case .modifiedOnDisk = conflict { conflict = nil }
        case .reload(let contents):
            replaceFromDisk(contents)
        case .conflict(let contents):
            conflict = .modifiedOnDisk(contents)
        case .deletedClean:
            saveTask?.cancel()
            return true
        case .deletedDirty:
            conflict = .deletedOnDisk
        }
        return false
    }

    /// Conflict resolution: take the disk version.
    func reloadFromDisk() {
        guard case .modifiedOnDisk(let contents) = conflict else { return }
        conflict = nil
        replaceFromDisk(contents)
    }

    /// Conflict resolution: overwrite (or recreate) the file with our version.
    func keepMine() {
        conflict = nil
        save(force: true)
    }

    private func replaceFromDisk(_ contents: String) {
        saveTask?.cancel()
        syncedText = contents
        text = contents
        saveTask?.cancel() // `text.didSet` scheduled a pointless save
        reloadGeneration += 1
    }
}

extension UserDefaults {
    static let autoNameKey = "autoNameFromFirstLine"

    var autoNameFromFirstLine: Bool {
        object(forKey: Self.autoNameKey) as? Bool ?? true
    }
}
