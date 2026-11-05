import Foundation
import MdCore

enum LibrarySort: String, CaseIterable, Identifiable {
    case name, modified
    var id: Self { self }
    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .modified: String(localized: "Date Modified")
        }
    }
}

/// A node in the sidebar tree. `children` is `nil` for notes (leaves).
struct LibraryNode: Identifiable, Hashable {
    /// Path relative to the library root, `/`-separated.
    let id: String
    let name: String
    let isDir: Bool
    let modified: Date
    var children: [LibraryNode]?

    var displayName: String {
        isDir ? name : (name as NSString).deletingPathExtension
    }
}

enum LibraryTree {
    /// Builds a sorted tree from the flat, path-sorted entries returned by the core.
    /// Folders always come first, sorted by name; notes follow `sort`.
    static func build(_ entries: [LibraryEntry], sort: LibrarySort) -> [LibraryNode] {
        var childrenByParent: [String: [LibraryEntry]] = [:]
        for entry in entries {
            childrenByParent[parent(of: entry.relativePath), default: []].append(entry)
        }

        func nodes(under parent: String) -> [LibraryNode] {
            let items = (childrenByParent[parent] ?? []).map { entry in
                LibraryNode(
                    id: entry.relativePath,
                    name: (entry.relativePath as NSString).lastPathComponent,
                    isDir: entry.isDir,
                    modified: Date(timeIntervalSince1970: Double(entry.modifiedMs) / 1000),
                    children: entry.isDir ? nodes(under: entry.relativePath) : nil
                )
            }
            return items.sorted { a, b in
                if a.isDir != b.isDir { return a.isDir }
                if !a.isDir, sort == .modified, a.modified != b.modified {
                    return a.modified > b.modified
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
        return nodes(under: "")
    }

    static func parent(of relativePath: String) -> String {
        guard let slash = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[..<slash])
    }
}
