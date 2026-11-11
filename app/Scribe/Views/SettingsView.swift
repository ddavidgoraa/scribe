import SwiftUI

/// Settings (⌘,): grouped like System Settings, with visual choices and a live preview.
struct SettingsView: View {
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0
    @AppStorage(EditorSettings.columnKey) private var columnCharacters = 64
    @AppStorage(EditorSettings.focusKey) private var focusMode = false
    @AppStorage(EditorSettings.typewriterKey) private var typewriterMode = false
    @AppStorage(UserDefaults.autoNameKey) private var autoName = true

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 14) {
                    ForEach(AppAppearance.allCases) { option in
                        ChoiceCard(title: option.title, selected: appearance == option) {
                            AppearanceThumbnail(appearance: option)
                        } action: {
                            appearance = option
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            Section("Text") {
                HStack(spacing: 14) {
                    ForEach(EditorFont.allCases) { option in
                        ChoiceCard(title: option.title.replacingOccurrences(of: "iA Writer ", with: ""),
                                   selected: font == option) {
                            Text("Write")
                                .font(Font(option.font(size: 19)))
                                .foregroundStyle(Color.ink)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.paper)
                        } action: {
                            font = option
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                LabeledContent("Size") {
                    HStack(spacing: 10) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: $fontSize, in: EditorSettings.fontSizes, step: 1)
                            .frame(width: 180)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                        Text("\(Int(fontSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                LabeledContent("Line length") {
                    HStack(spacing: 8) {
                        Picker("Line length", selection: $columnCharacters) {
                            ForEach(MarkdownTheme.columnChoices, id: \.self) { Text("\($0)").tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        Text("characters").foregroundStyle(.secondary)
                    }
                }

                TextPreview(font: font, fontSize: fontSize)
            }

            Section("Writing") {
                Toggle(isOn: $focusMode) {
                    SettingLabel("Focus mode", detail: "Fade everything except the paragraph you're writing.", shortcut: "⌘D")
                }
                Toggle(isOn: $typewriterMode) {
                    SettingLabel("Typewriter mode", detail: "Keep the line you're writing in the middle of the window.", shortcut: "⌘T")
                }
            }

            Section("Notes") {
                Toggle(isOn: $autoName) {
                    SettingLabel("Name notes after their first line",
                                 detail: "Untitled notes, and notes named after their first line, are renamed when it changes. Rename a note yourself to stop.")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: appearance) { appearance.apply() }
    }
}

/// A selectable tile: a small picture with a caption, outlined in the accent color when chosen.
private struct ChoiceCard<Preview: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder let preview: () -> Preview
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                preview()
                    .frame(width: 96, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(selected ? Color.accentBlue : Color.line, lineWidth: selected ? 2.5 : 1)
                    )
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A tiny Scribe window in light, dark, or half-and-half for "Match System".
private struct AppearanceThumbnail: View {
    let appearance: AppAppearance

    var body: some View {
        switch appearance {
        case .light: page(dark: false)
        case .dark: page(dark: true)
        case .system:
            HStack(spacing: 0) {
                page(dark: false).frame(width: 48, alignment: .leading).clipped()
                page(dark: true).frame(width: 48, alignment: .trailing).clipped()
            }
        }
    }

    private func page(dark: Bool) -> some View {
        let paper = Color(nsColor: NSColor(hex: dark ? 0x161617 : 0xFFFFFF))
        let ink = Color(nsColor: NSColor(hex: dark ? 0xEDEDED : 0x1D1D1F))
        return ZStack(alignment: .topLeading) {
            paper
            HStack(spacing: 3) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.8)).frame(width: 4, height: 4) }
            }
            .padding(6)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(ink).frame(width: 34, height: 4)
                Capsule().fill(ink.opacity(0.45)).frame(width: 56, height: 3)
                Capsule().fill(ink.opacity(0.45)).frame(width: 48, height: 3)
                Capsule().fill(Color.accentBlue).frame(width: 2, height: 7)
            }
            .padding(.top, 18)
            .padding(.leading, 20)
        }
        .frame(width: 96, height: 62)
    }
}

/// A few lines in the chosen typeface and size, on the editor's paper.
private struct TextPreview: View {
    let font: EditorFont
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("The quiet page")
                .font(Font(font.font(size: CGFloat(fontSize) * 1.15, bold: true)))
            Text("Write first, format later. Markdown symbols fade away once your cursor moves on.")
                .font(Font(font.font(size: CGFloat(fontSize))))
                .lineSpacing(CGFloat(fontSize) * 0.35)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.line))
        .padding(.vertical, 2)
        .accessibilityLabel("Text preview")
    }
}

/// A setting's name with an explanation underneath and an optional shortcut.
private struct SettingLabel: View {
    let title: String
    let detail: String
    var shortcut: String?

    init(_ title: String, detail: String, shortcut: String? = nil) {
        self.title = title
        self.detail = detail
        self.shortcut = shortcut
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
