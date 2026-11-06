import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaults.autoNameKey) private var autoName = true

    var body: some View {
        Form {
            Toggle("Name notes after their first line", isOn: $autoName)
            Text("Applies to Untitled notes and notes whose name matches their first line. Rename a note to stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
    }
}
