import AppKit

extension NSAttributedString.Key {
    /// A `Decoration` drawn by `DecoratedLayoutFragment` at the attributed character.
    static let scribeDecoration = NSAttributedString.Key("ScribeDecoration")
}

/// Something drawn over hidden source text: rendered math or an image.
final class Decoration: NSObject {
    enum Placement {
        /// In the line, on the text baseline (inline math). Space is reserved with `.kern`.
        case inline
        /// Filling a line whose height was reserved (block math, images).
        case block
        /// Below the line, in reserved paragraph spacing (live preview of block math).
        case below
    }

    let image: NSImage
    let size: CGSize
    /// Distance from the baseline to the top of the image (inline placement).
    let ascent: CGFloat
    let placement: Placement
    /// Draw the image as a mask filled with the text color (math), not as-is (photos).
    let tinted: Bool

    init(image: NSImage, size: CGSize, ascent: CGFloat = 0, placement: Placement, tinted: Bool = false) {
        self.image = image
        self.size = size
        self.ascent = ascent
        self.placement = placement
        self.tinted = tinted
    }

    static let blockPadding: CGFloat = 8
}
