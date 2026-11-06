import AppKit

/// Draws `Decoration`s (rendered math, images) over the hidden source of a paragraph.
final class DecoratedLayoutFragment: NSTextLayoutFragment {
    private static let overflow: CGFloat = 24

    override var renderingSurfaceBounds: CGRect {
        // A line of hidden characters is ~0 wide, but its decoration spans the column;
        // inline formulas may also be taller than their line.
        let width = textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
        return super.renderingSurfaceBounds
            .union(CGRect(x: 0, y: 0, width: width, height: layoutFragmentFrame.height))
            .insetBy(dx: 0, dy: -Self.overflow)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        var decorations: [(Decoration, Int, NSTextLineFragment)] = []
        for line in textLineFragments {
            let string = line.attributedString
            let range = line.characterRange
            guard range.length > 0, NSMaxRange(range) <= string.length else { continue }
            string.enumerateAttribute(.scribeDecoration, in: range) { value, attrRange, _ in
                if let decoration = value as? Decoration { decorations.append((decoration, attrRange.location, line)) }
            }
        }
        guard !decorations.isEmpty else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let tint = textColor()
        for (decoration, index, line) in decorations {
            draw(decoration, at: index, in: line, origin: point, tint: tint, context: context)
        }
    }

    /// The label color as the text view shows it (its own appearance, not the app's).
    private func textColor() -> CGColor {
        let appearance = textLayoutManager?.textContainer?.textView?.effectiveAppearance
            ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
        var color = NSColor.black.cgColor
        appearance.performAsCurrentDrawingAppearance { color = NSColor.labelColor.cgColor }
        return color
    }

    private func draw(_ decoration: Decoration, at index: Int, in line: NSTextLineFragment,
                      origin: CGPoint, tint: CGColor, context: CGContext) {
        let bounds = line.typographicBounds
        let x = origin.x + bounds.minX + line.locationForCharacter(at: index).x
        let y: CGFloat
        switch decoration.placement {
        case .inline:
            let baseline = origin.y + bounds.minY + line.glyphOrigin.y
            y = baseline - decoration.ascent
        case .block:
            y = origin.y + bounds.minY + (bounds.height - decoration.size.height) / 2
        case .below:
            y = origin.y + bounds.maxY + Decoration.blockPadding
        }
        let rect = CGRect(origin: CGPoint(x: x, y: y), size: decoration.size)
        guard decoration.tinted else {
            decoration.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        // Mask: draw the black image, then fill only its pixels with the text color.
        context.saveGState()
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        decoration.image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        context.setFillColor(tint)
        context.setBlendMode(.sourceIn)
        context.fill(rect)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
