import AppKit
import SwiftUI

/// Settings (⌘,) in the Paper style: a live miniature of the editor on top, then a
/// quiet list of options — small-caps section headers, hairline dividers, pill
/// controls with the same accent selection as the library.
struct SettingsView: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0
    @AppStorage(EditorSettings.columnKey) private var columnCharacters = 64
    @AppStorage(EditorSettings.focusKey) private var focusMode = false
    @AppStorage(EditorSettings.typewriterKey) private var typewriterMode = false
    @AppStorage(UserDefaults.autoNameKey) private var autoName = true
    @Environment(\.colorScheme) private var systemScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EditorPreview(
                dark: appearance == .dark || (appearance == .system && systemScheme == .dark),
                font: font, fontSize: fontSize, columnCharacters: columnCharacters, focusMode: focusMode
            )
            .padding(.top, 44) // below the window buttons
            .padding(.horizontal, 28)
            .padding(.bottom, 8)

            SettingsSection("Appearance") {
                SettingsRow("Theme") {
                    PillPicker(selection: $appearance, options: AppAppearance.allCases) { option in
                        Label(option.shortTitle, systemImage: option.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                }
            }

            SettingsSection("Text") {
                SettingsRow("Typeface") {
                    PillPicker(selection: $font, options: EditorFont.allCases) { option in
                        Text(option.shortTitle).font(Font(option.font(size: 13)))
                    }
                }
                SettingsRow("Size") {
                    SizeStepper(value: $fontSize, range: EditorSettings.fontSizes)
                }
                SettingsRow("Line length", detail: "Characters per line") {
                    PillPicker(selection: $columnCharacters, options: MarkdownTheme.columnChoices) { Text("\($0)") }
                }
            }

            SettingsSection("Writing") {
                SettingsRow("Focus mode", detail: "Fade all but the paragraph you're writing", shortcut: "⌘D") {
                    PaperToggle(isOn: $focusMode)
                }
                SettingsRow("Typewriter mode", detail: "Keep the current line in the middle", shortcut: "⌘T") {
                    PaperToggle(isOn: $typewriterMode)
                }
            }

            SettingsSection("Notes", isLast: true) {
                SettingsRow("Name notes after their first line",
                            detail: "Untitled notes follow their first line until you rename them") {
                    PaperToggle(isOn: $autoName)
                }
            }
        }
        .frame(width: 560)
        .background(Color.paper)
        .background(PaperWindowStyle())
        .onChange(of: appearance) { appearance.apply() }
    }
}

// MARK: Layout

/// A section: small-caps header like the library panel's, then rows split by hairlines.
private struct SettingsSection<Content: View>: View {
    let title: String
    let isLast: Bool
    @ViewBuilder let content: Content

    init(_ title: String, isLast: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.isLast = isLast
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).sectionHeader()
                .padding(.top, 22)
                .padding(.bottom, 4)
            content // each row draws the hairline above it
        }
        .padding(.horizontal, 28)
        .padding(.bottom, isLast ? 28 : 0)
    }
}

/// One setting: name (and a quiet explanation) on the left, its control on the right.
private struct SettingsRow<Control: View>: View {
    let title: String
    var detail: String?
    var shortcut: String?
    @ViewBuilder let control: Control

    init(_ title: String, detail: String? = nil, shortcut: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(title).font(.system(size: 13.5)).foregroundStyle(Color.ink)
                    if let shortcut { ShortcutChip(shortcut) }
                }
                if let detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(Color.ink2)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}

// MARK: Controls

/// Segmented choice in the app's pill style: the selected option sits in the accent
/// tint used for the open note in the library, so it is unmistakable.
private struct PillPicker<Option: Hashable, Label: View>: View {
    @Binding var selection: Option
    let options: [Option]
    @ViewBuilder let label: (Option) -> Label

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    label(option)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.accentText : Color.ink2)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(selected ? Color.accentSoft : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(PillTrack())
        .fixedSize() // never squeezed by the row: the outline must fit the options
    }
}

/// The track behind pill controls: one shape, filled and outlined together.
private struct PillTrack: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.paper2)
            .overlay(Capsule(style: .continuous).inset(by: 0.5).stroke(Color.line, lineWidth: 1))
    }
}

/// − 16 pt + in a pill, matching the status pills.
private struct SizeStepper: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack(spacing: 0) {
            step("minus", by: -1).disabled(value <= range.lowerBound)
            Text("\(Int(value)) pt")
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
                .frame(width: 52)
            step("plus", by: 1).disabled(value >= range.upperBound)
        }
        .padding(3)
        .background(PillTrack())
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Size")
        .accessibilityValue("\(Int(value)) points")
        .accessibilityAdjustableAction { direction in
            value = min(range.upperBound, max(range.lowerBound, value + (direction == .increment ? 1 : -1)))
        }
    }

    private func step(_ symbol: String, by delta: Double) -> some View {
        Button { value = min(range.upperBound, max(range.lowerBound, value + delta)) } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.ink2)
                .frame(width: 30, height: 26)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The system switch, in the app's accent.
private struct PaperToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(Color.accentBlue)
            .controlSize(.small)
    }
}

/// A shortcut shown like the status pills.
private struct ShortcutChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.ink3)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Color.line))
    }
}

// MARK: Live preview

/// A miniature Scribe window showing the chosen appearance, typeface, size, line
/// length and focus mode — with the app's own fonts and colors.
private struct EditorPreview: View {
    let dark: Bool
    let font: EditorFont
    let fontSize: Double
    let columnCharacters: Int
    let focusMode: Bool

    /// The preview is a scaled-down window.
    private let scale: CGFloat = 0.72

    var body: some View {
        let colors = PreviewColors(dark: dark)
        let size = CGFloat(fontSize) * scale
        let theme = MarkdownTheme(font: font, fontSize: CGFloat(fontSize), columnCharacters: columnCharacters)
        let column = min(theme.columnWidth * scale, 440)
        ZStack(alignment: .top) {
            colors.paper
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(colors.lights).frame(width: 7, height: 7) }
                Spacer()
            }
            .padding(10)
            Text("Trip to Kraków")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(colors.ink3)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: size * 0.7) {
                Text("Trip to Kraków")
                    .font(Font(font.font(size: size * 1.25, bold: true)))
                    .opacity(focusMode ? 0.3 : 1)
                (Text("The train left right on time. Fog outside — the perfect moment to ")
                    + Text("finish the draft").font(Font(font.font(size: size, bold: true)))
                    + Text(" and stop fiddling with commas."))
                    .font(Font(font.font(size: size)))
                    .lineSpacing(size * 0.45)
                    .overlay(alignment: .bottomTrailing) { caret(colors, size: size) }
                Text("Tomorrow: the castle, the river, and a very long lunch.")
                    .font(Font(font.font(size: size)))
                    .lineSpacing(size * 0.45)
                    .opacity(focusMode ? 0.3 : 1)
            }
            .foregroundStyle(colors.ink)
            .frame(width: column, alignment: .leading)
            .padding(.top, 40)
            .animation(.easeOut(duration: 0.2), value: focusMode)
        }
        .frame(height: 172)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous).strokeBorder(colors.line))
        .shadow(color: .black.opacity(dark ? 0.3 : 0.06), radius: 14, y: 8)
        .animation(.easeOut(duration: 0.2), value: dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the editor")
    }

    private func caret(_ colors: PreviewColors, size: CGFloat) -> some View {
        Rectangle().fill(colors.accent).frame(width: 1.5, height: size * 1.2).offset(x: 3)
    }
}

/// The Paper palette for the preview's own appearance (independent of the window's).
private struct PreviewColors {
    let paper, ink, ink3, line, lights, accent: Color

    init(dark: Bool) {
        func c(_ light: UInt32, _ darkHex: UInt32) -> Color { Color(nsColor: NSColor(hex: dark ? darkHex : light)) }
        paper = c(0xFFFFFF, 0x161617)
        ink = c(0x1D1D1F, 0xEDEDED)
        ink3 = c(0xAEAEB2, 0x636366)
        line = c(0xE5E5EA, 0x2C2C2E)
        lights = c(0xDCDCE0, 0x3A3A3C)
        accent = c(0x1A9FFF, 0x3BAFFF)
    }
}

// MARK: Window

/// Gives the Settings window the main window's chrome: no title, content up to the top.
private struct PaperWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
            window.backgroundColor = Palette.paper
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

// MARK: Labels

private extension AppAppearance {
    var shortTitle: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
}

private extension EditorFont {
    var shortTitle: String { title.replacingOccurrences(of: "iA Writer ", with: "") }
}
