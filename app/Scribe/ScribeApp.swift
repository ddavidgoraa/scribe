import SwiftUI

@main
struct ScribeApp: App {
    @State private var library = LibraryModel()

    var body: some Scene {
        Window("Scribe", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 700, minHeight: 450)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    library.flush()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    library.flush()
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { library.newNote() }
                    .keyboardShortcut("n")
                    .disabled(library.root == nil)
                Button("Open Library…") { library.chooseLibrary() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .sidebar) {
                Picker("Sort Notes By", selection: $library.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        Settings {
            SettingsView()
        }
    }
}
