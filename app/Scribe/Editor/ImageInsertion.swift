import AppKit
import MdCore

/// Pasting and dropping images into a note.
///
/// - Image files inside the library are linked where they are (relative path).
/// - Image files from elsewhere are copied to `assets/` next to the note.
/// - Raw image data (screenshots, images copied from apps) is saved there as PNG.
///
/// Each image is inserted as `![alt](link)` on its own line, so it previews as a block.
enum ImageInsertion {
    struct Image: Equatable {
        let alt: String
        let link: String
    }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "webp", "bmp", "svg"]

    /// Whether a paste/drop should be handled as images rather than text.
    static func containsImages(_ pasteboard: NSPasteboard) -> Bool {
        if !imageFileURLs(pasteboard).isEmpty { return true }
        if !fileURLs(pasteboard).isEmpty { return false } // other files: default behaviour
        guard pasteboard.availableType(from: [.png, .tiff]) != nil else { return false }
        // Rich text copies may carry a picture too; prefer the text unless it's just a URL.
        guard let string = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty else { return true }
        return URL(string: string)?.scheme != nil && !string.contains(" ")
    }

    /// Saves or links the images on `pasteboard` for the note at `note`.
    static func images(from pasteboard: NSPasteboard, note: URL, libraryRoot: URL?, now: Date = Date()) throws -> [Image] {
        guard containsImages(pasteboard) else { return [] }
        let timestamp = Self.timestamp(now)
        let noteDir = note.deletingLastPathComponent()

        let files = imageFileURLs(pasteboard)
        if !files.isEmpty {
            return try files.map { url in
                let target = isInside(url, libraryRoot)
                    ? url
                    : URL(fileURLWithPath: try importAsset(notePath: note.path, sourcePath: url.path, timestamp: timestamp))
                return Image(alt: url.deletingPathExtension().lastPathComponent,
                             link: relativeLink(fromDir: noteDir.path, target: target.path))
            }
        }
        guard let png = pngData(pasteboard) else { return [] }
        let saved = try saveAsset(notePath: note.path, data: png, extension: "png", timestamp: timestamp)
        return [Image(alt: "", link: relativeLink(fromDir: noteDir.path, target: saved))]
    }

    /// Markdown for `images`, one per line, with line breaks added so they stand alone.
    static func markdown(_ images: [Image], in text: NSString, replacing range: NSRange) -> String {
        var result = images.map { "![\(escape($0.alt))](\($0.link))" }.joined(separator: "\n")
        if range.location > 0, text.character(at: range.location - 1) != 0x0A { result = "\n" + result }
        let end = NSMaxRange(range)
        if end < text.length, text.character(at: end) != 0x0A { result += "\n" }
        return result
    }

    // MARK: Helpers

    private static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private static func imageFileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        fileURLs(pasteboard).filter { imageExtensions.contains($0.pathExtension.lowercased()) }
    }

    private static func pngData(_ pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func isInside(_ url: URL, _ root: URL?) -> Bool {
        guard let root else { return false }
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    private static func escape(_ alt: String) -> String {
        alt.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}
