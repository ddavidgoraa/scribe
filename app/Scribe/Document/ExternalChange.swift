import Foundation

/// What to do when a note may have changed on disk behind our back.
enum ExternalChange: Equatable {
    /// Disk matches what we last loaded or saved (often our own write).
    case none
    /// We have no unsaved edits: take the disk version silently.
    case reload(String)
    /// Disk changed and we have unsaved edits: ask the user.
    case conflict(String)
    /// File is gone and we have no unsaved edits: close it.
    case deletedClean
    /// File is gone but we have unsaved edits: ask the user.
    case deletedDirty

    /// - Parameters:
    ///   - disk: current file contents, or `nil` if the file no longer exists
    ///   - synced: contents we last read from or wrote to disk
    ///   - current: contents in the editor
    static func resolve(disk: String?, synced: String, current: String) -> ExternalChange {
        let dirty = current != synced
        guard let disk else { return dirty ? .deletedDirty : .deletedClean }
        if disk == synced { return .none }
        if disk == current || !dirty { return .reload(disk) }
        return .conflict(disk)
    }
}
