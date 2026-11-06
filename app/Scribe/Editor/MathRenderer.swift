import AppKit
import SwiftMath

/// Renders LaTeX with SwiftMath, cached. Images are black masks; `DecoratedLayoutFragment`
/// tints them with the text color of the view's appearance (light/dark).
@MainActor
final class MathRenderer {
    struct Rendered {
        let image: NSImage
        let size: CGSize
        let ascent: CGFloat
    }

    struct Failure: Error {
        let message: String
    }

    static let shared = MathRenderer()

    private struct Key: Hashable {
        let latex: String
        let display: Bool
        let fontSize: CGFloat
    }

    private var cache: [Key: Result<Rendered, Failure>] = [:]

    func render(_ latex: String, display: Bool, fontSize: CGFloat) -> Result<Rendered, Failure> {
        let key = Key(latex: latex, display: display, fontSize: fontSize)
        if let cached = cache[key] { return cached }
        let result = Self.render(key)
        if cache.count > 500 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private static func render(_ key: Key) -> Result<Rendered, Failure> {
        guard !key.latex.isEmpty else { return .failure(Failure(message: "Empty formula")) }
        var math = MathImage(
            latex: key.latex,
            fontSize: key.fontSize,
            textColor: .black,
            labelMode: key.display ? .display : .text,
            textAlignment: .left
        )
        let (error, image, info) = math.asImage()
        guard let image, let info else {
            return .failure(Failure(message: error?.localizedDescription ?? "Invalid formula"))
        }
        // Mirror SwiftMath's vertical centering to find the baseline (from the top).
        let height = image.size.height
        let content = max(info.ascent + info.descent, key.fontSize / 2)
        let baselineFromBottom = (height - content) / 2 + info.descent
        return .success(Rendered(image: image, size: image.size, ascent: height - baselineFromBottom))
    }
}
