import SwiftUI

struct SettingsView: View {
    @AppStorage(UserDefaults.autoNameKey) private var autoName = true

    var body: some View {
        Form {
            Toggle("Name new notes from their first line", isOn: $autoName)
        }
        .padding(20)
        .frame(width: 420)
    }
}
