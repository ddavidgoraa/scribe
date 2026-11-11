import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaults.autoNameKey) private var autoName = true
    @AppStorage(EditorSettings.fontKey) private var font = EditorFont.duo
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0
    @AppStorage(EditorSettings.columnKey) private var columnCharacters = 64
    @AppStorage(AppAppearance.key) private var appearance = AppAppearance.system

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { appearance.apply() }
            Picker("Font", selection: $font) {
                ForEach(EditorFont.allCases) { Text($0.title).tag($0) }
            }
            Stepper(value: $fontSize, in: EditorSettings.fontSizes, step: 1) {
                Text("Size: \(Int(fontSize)) pt")
            }
            Picker("Line length", selection: $columnCharacters) {
                ForEach(MarkdownTheme.columnChoices, id: \.self) { Text("\($0) characters").tag($0) }
            }
            Toggle("Name notes after their first line", isOn: $autoName)
            Text("Applies to Untitled notes and notes whose name matches their first line. Rename a note to stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
    }
}
