import AppKit

/// Printing a note as a clean document: no Markdown syntax, math and images typeset,
/// light colors on paper, pages that never split a line, title and page numbers below.
@MainActor
enum NotePrinter {
    /// Body text size on paper (the editor's size is meant for the screen).
    static let printFontSize: CGFloat = 11.5
    static let margins = NSEdgeInsets(top: 60, left: 64, bottom: 64, right: 64)

    /// Print settings based on the user's (paper size, printer), with Scribe's margins.
    static func printInfo(from base: NSPrintInfo = .shared) -> NSPrintInfo {
        let info = base.copy() as! NSPrintInfo
        info.topMargin = margins.top
        info.leftMargin = margins.left
        info.bottomMargin = margins.bottom
        info.rightMargin = margins.right
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.dictionary()[NSPrintInfo.AttributeKey.headerAndFooter] = true
        return info
    }

    /// A laid-out, paper-wide view of the note, ready for `NSPrintOperation`.
    static func makeView(text: String, title: String, baseURL: URL?, font: EditorFont,
                         printInfo: NSPrintInfo) -> PrintableNoteView {
        let width = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let theme = MarkdownTheme(font: font, fontSize: printFontSize)
        let view = PrintableNoteView(title: title, theme: theme, baseURL: baseURL, width: width)
        view.load(text)
        return view
    }

    /// Shows the print panel for a note (PDF export is in the panel too).
    static func print(text: String, title: String, baseURL: URL?, font: EditorFont, window: NSWindow?) {
        let info = printInfo()
        let view = makeView(text: text, title: title, baseURL: baseURL, font: font, printInfo: info)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        if let window {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}

/// The note as it goes on paper: a TextKit 2 view styled by the highlighter in print mode.
final class PrintableNoteView: NSTextView {
    let title: String
    private let highlighter: MarkdownHighlighter
    private let fragments = DecoratedFragmentProvider()
    /// Held strongly: the layout manager only references its content manager weakly.
    private let contentStorage = NSTextContentStorage()

    init(title: String, theme: MarkdownTheme, baseURL: URL?, width: CGFloat) {
        self.title = title
        highlighter = MarkdownHighlighter(theme: theme)
        highlighter.baseURL = baseURL
        highlighter.printMode = true
        highlighter.maxImageSize = CGSize(width: width, height: 520)
        highlighter.resetCaret(nil) // nothing is being edited: everything typeset

        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: 0))
        container.widthTracksTextView = true
        layoutManager.textContainer = container
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        contentStorage.addTextLayoutManager(layoutManager)
        layoutManager.delegate = fragments
        appearance = NSAppearance(named: .aqua) // ink on white paper, whatever the screen shows
        drawsBackground = false
        isEditable = false
        isSelectable = false
        textContainerInset = .zero
        isVerticallyResizable = true
        isHorizontallyResizable = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Sets the text, styles it for print and sizes the view to the content.
    func load(_ text: String) {
        string = text
        if let storage = textStorage {
            highlighter.highlightAll(storage)
            Self.removeHiddenSyntax(from: storage)
        }
        guard let layoutManager = textLayoutManager else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let height = ceil(layoutManager.usageBoundsForTextContainer.height)
        setFrameSize(NSSize(width: frame.width, height: max(height, 1)))
    }

    /// The editor hides syntax with a tiny transparent font, which a PDF would still carry
    /// as (invisible) text. On paper the syntax goes for real: hidden runs are removed, and
    /// a run that anchors a drawing (formula, image, bullet, box) keeps one tiny space
    /// carrying it (a real glyph, so its kern reserves the drawing's width), plus its line
    /// break for block drawings.
    static func removeHiddenSyntax(from storage: NSTextStorage) {
        var runs: [NSRange] = []
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let font = value as? NSFont, font.pointSize < 1 {
                if let last = runs.last, NSMaxRange(last) == range.location {
                    runs[runs.count - 1] = NSUnionRange(last, range)
                } else {
                    runs.append(range)
                }
            }
        }
        let text = storage.string as NSString
        storage.beginEditing()
        for run in runs.reversed() {
            // Adjacent hidden syntax merges into one run (e.g. a task item's `- ` and `[ ]`),
            // so the drawing can sit on any of its characters.
            var anchor: Int?
            storage.enumerateAttribute(.scribeDecoration, in: run) { value, range, stop in
                if value != nil { anchor = range.location; stop.pointee = true }
            }
            guard let anchor else {
                storage.deleteCharacters(in: run)
                continue
            }
            let attributes = storage.attributes(at: anchor, effectiveRange: nil)
            let endsLine = text.substring(with: run).hasSuffix("\n")
            let replacement = NSAttributedString(string: endsLine ? " \n" : " ", attributes: attributes)
            storage.replaceCharacters(in: run, with: replacement)
        }
        storage.endEditing()
    }

    // MARK: Pagination

    /// Moves a page break up so that no line (or formula, or image) is cut in half.
    override func adjustPageHeightNew(_ newBottom: UnsafeMutablePointer<CGFloat>, top oldTop: CGFloat,
                                      bottom proposedBottom: CGFloat, limit bottomLimit: CGFloat) {
        newBottom.pointee = proposedBottom
        guard let layoutManager = textLayoutManager else { return }
        let origin = textContainerOrigin
        layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location,
                                                   options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            guard frame.minY < proposedBottom else { return false }
            guard frame.maxY > proposedBottom else { return true }
            for line in fragment.textLineFragments {
                let top = frame.minY + line.typographicBounds.minY
                let bottom = frame.minY + line.typographicBounds.maxY
                if top < proposedBottom, bottom > proposedBottom, top > bottomLimit {
                    newBottom.pointee = top
                    break
                }
            }
            return false
        }
    }

    // MARK: Header and footer

    override var pageHeader: NSAttributedString { NSAttributedString() }

    override var pageFooter: NSAttributedString {
        let operation = NSPrintOperation.current
        let page = operation?.currentPage ?? 1
        let total = operation.map { $0.pageRange.length } ?? 0
        let number = total > 1 ? "\(page) / \(total)" : "\(page)"
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: "\(title)  ·  \(number)", attributes: [
            .font: NSFont.systemFont(ofSize: 8.5),
            .foregroundColor: NSColor(hex: 0x8E8E93),
            .paragraphStyle: paragraph,
        ])
    }
}

/// Typeset replacements for syntax the editor shows as source (used when printing).
@MainActor
enum PrintGlyphs {
    /// "•" followed by a gap, sitting on the text baseline.
    static func bullet(font: NSFont) -> Decoration {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let bullet = NSAttributedString(string: "•", attributes: attributes)
        let gap = font.pointSize * 0.55
        let size = CGSize(width: ceil(bullet.size().width + gap), height: ceil(font.ascender - font.descender))
        let image = NSImage(size: size, flipped: false) { _ in
            bullet.draw(at: NSPoint(x: 0, y: -font.descender))
            return true
        }
        return Decoration(image: image, size: size, ascent: font.ascender, placement: .inline, tinted: true)
    }

    /// An empty or checked box, about the height of capital letters.
    static func checkbox(checked: Bool, font: NSFont) -> Decoration {
        let side = ceil(font.capHeight * 1.15)
        let gap = font.pointSize * 0.15
        let size = CGSize(width: side + gap, height: side)
        let image = NSImage(size: size, flipped: false) { _ in
            let box = NSRect(x: 0.5, y: 0.5, width: side - 1, height: side - 1)
            let path = NSBezierPath(roundedRect: box, xRadius: side * 0.2, yRadius: side * 0.2)
            NSColor.black.set()
            if checked {
                path.fill()
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: side * 0.24, y: side * 0.52))
                tick.line(to: NSPoint(x: side * 0.43, y: side * 0.3))
                tick.line(to: NSPoint(x: side * 0.77, y: side * 0.72))
                tick.lineWidth = max(1.2, side * 0.12)
                tick.lineCapStyle = .round
                tick.lineJoinStyle = .round
                NSColor.white.set()
                tick.stroke()
            } else {
                path.lineWidth = 1
                path.stroke()
            }
            return true
        }
        return Decoration(image: image, size: size, ascent: side, placement: .inline, tinted: true)
    }

    /// A thin full-width line (thematic break).
    static func rule(width: CGFloat) -> Decoration {
        let size = CGSize(width: width, height: 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.25).setFill()
            rect.fill()
            return true
        }
        return Decoration(image: image, size: size, placement: .block, tinted: true)
    }
}
