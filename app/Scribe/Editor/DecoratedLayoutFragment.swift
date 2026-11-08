import AppKit

/// One paragraph of the editor. Draws, around the text:
/// - code block backgrounds spanning the column,
/// - `Decoration`s (rendered math, images) over hidden source,
/// - dimming when focus mode highlights another paragraph.
final class DecoratedLayoutFragment: NSTextLayoutFragment {
    private static let overflow: CGFloat = 24
    static let blockInset: CGFloat = 10
    static let dimmedAlpha: CGFloat = 0.3

    private var textView: MarkdownTextView? {
        textLayoutManager?.textContainer?.textView as? MarkdownTextView
    }

    private var columnWidth: CGFloat {
        textLayoutManager?.textContainer?.size.width ?? layoutFragmentFrame.width
    }

    override var renderingSurfaceBounds: CGRect {
        // A line of hidden characters is ~0 wide, but its decoration spans the column;
        // inline formulas may also be taller than their line.
        super.renderingSurfaceBounds
            .union(CGRect(x: -Self.blockInset, y: 0, width: columnWidth + 2 * Self.blockInset,
                          height: layoutFragmentFrame.height))
            .insetBy(dx: 0, dy: -Self.overflow)
    }

    /// Character range of this paragraph in the document.
    private var characterRange: NSRange? {
        guard let tlm = textLayoutManager, let range = rangeInElement as NSTextRange? else { return nil }
        let start = tlm.offset(from: tlm.documentRange.location, to: range.location)
        let length = tlm.offset(from: range.location, to: range.endLocation)
        return NSRange(location: start, length: length)
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let dimmed = characterRange.map { textView?.isDimmed($0) ?? false } ?? false
        if dimmed {
            context.saveGState()
            context.setAlpha(Self.dimmedAlpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if dimmed {
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
        drawBlockBackground(at: point, in: context)
        super.draw(at: point, in: context)
        drawDecorations(at: point, in: context)
    }

    private func drawBlockBackground(at point: CGPoint, in context: CGContext) {
        guard let line = textLineFragments.first, line.characterRange.length > 0,
              line.characterRange.location < line.attributedString.length,
              let color = line.attributedString.attribute(.scribeBlockBackground, at: line.characterRange.location,
                                                          effectiveRange: nil) as? NSColor
        else { return }
        let rect = CGRect(x: point.x - Self.blockInset, y: point.y,
                          width: columnWidth + 2 * Self.blockInset, height: layoutFragmentFrame.height)
        context.setFillColor(resolved(color))
        context.fill(rect)
    }

    private func drawDecorations(at point: CGPoint, in context: CGContext) {
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
        let tint = resolved(.labelColor)
        for (decoration, index, line) in decorations {
            draw(decoration, at: index, in: line, origin: point, tint: tint, context: context)
        }
    }

    /// A dynamic color as the text view shows it (its own appearance, not the app's).
    private func resolved(_ color: NSColor) -> CGColor {
        let appearance = textLayoutManager?.textContainer?.textView?.effectiveAppearance
            ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
        var cgColor = NSColor.black.cgColor
        appearance.performAsCurrentDrawingAppearance { cgColor = color.cgColor }
        return cgColor
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
