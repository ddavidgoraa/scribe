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

    /// Whether focus mode fades this paragraph. TextKit draws an NSTextView's fragments
    /// on the main thread; anywhere else, draw undimmed.
    private var isDimmed: Bool {
        guard Thread.isMainThread, let range = characterRange else { return false }
        nonisolated(unsafe) let fragment = self
        return MainActor.assumeIsolated { fragment.textView?.isDimmed(range) ?? false }
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let dimmed = isDimmed
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
        let tint = resolved(Palette.ink)
        for (decoration, index, line) in decorations {
            draw(decoration, at: index, in: line, origin: point, tint: tint, context: context)
        }
    }

    /// A dynamic color as the text view shows it (its own appearance, not the app's).
    private func resolved(_ color: NSColor) -> CGColor {
        func resolve(in appearance: NSAppearance) -> CGColor {
            var cgColor = NSColor.black.cgColor
            appearance.performAsCurrentDrawingAppearance { cgColor = color.cgColor }
            return cgColor
        }
        // TextKit draws an NSTextView's fragments on the main thread.
        guard Thread.isMainThread else { return resolve(in: NSAppearance.currentDrawing()) }
        nonisolated(unsafe) let fragment = self
        return MainActor.assumeIsolated {
            resolve(in: fragment.textLayoutManager?.textContainer?.textView?.effectiveAppearance
                ?? NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!)
        }
    }

    private func draw(_ decoration: Decoration, at index: Int, in line: NSTextLineFragment,
                      origin: CGPoint, tint: CGColor, context: CGContext) {
        let bounds = line.typographicBounds
        var x = origin.x + bounds.minX + line.locationForCharacter(at: index).x
        if decoration.tinted, decoration.placement != .inline {
            // Block math is centered in the column, like a displayed equation.
            let padding = textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
            x = origin.x + max(0, (columnWidth - 2 * padding - decoration.size.width) / 2) + padding
        }
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
        // On paper the text is black anyway, and masks don't survive PDF and printer
        // contexts: draw the (vector) image as it is.
        let printing = !(NSGraphicsContext.current?.isDrawingToScreen ?? true)
        guard decoration.tinted, !printing else {
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

/// Lays out every paragraph with `DecoratedLayoutFragment` (editor and print views).
final class DecoratedFragmentProvider: NSObject, NSTextLayoutManagerDelegate {
    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation,
                           in textElement: NSTextElement) -> NSTextLayoutFragment {
        DecoratedLayoutFragment(textElement: textElement, range: textElement.elementRange)
    }
}
