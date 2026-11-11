import SwiftUI

@main
struct ScribeApp: App {
    @State private var library = LibraryModel()
    @AppStorage(EditorSettings.typewriterKey) private var typewriterMode = false
    @AppStorage(EditorSettings.focusKey) private var focusMode = false
    @AppStorage(EditorSettings.fontSizeKey) private var fontSize = 16.0

    init() {
        EditorFonts.registerBundledFonts()
    }

    var body: some Scene {
        Window("Scribe", id: "main") {
            ContentView()
                .environment(library)
                .frame(minWidth: 640, minHeight: 420)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    library.flush()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    library.flush()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Note") { library.newNote() }
                    .keyboardShortcut("n")
                    .disabled(library.root == nil)
                Button("Open Library…") { library.chooseLibrary() }
                    .keyboardShortcut("o")
                Divider()
                Button("Quick Open…") { library.isQuickOpenPresented.toggle() }
                    .keyboardShortcut("p")
                    .disabled(library.root == nil)
                Button("Search Library…") { library.focusSearch() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(library.root == nil)
            }
            CommandGroup(replacing: .printItem) {}
            CommandGroup(after: .pasteboard) {
                Button("Copy as HTML") { send(#selector(MarkdownTextView.copyAsHTML(_:))) }
                    .keyboardShortcut("c", modifiers: [.command, .option])
            }
            TextEditingCommands()
            CommandMenu("Format") {
                Button("Bold") { send(#selector(MarkdownTextView.toggleBold(_:))) }
                    .keyboardShortcut("b")
                Button("Italic") { send(#selector(MarkdownTextView.toggleItalic(_:))) }
                    .keyboardShortcut("i")
                Button("Strikethrough") { send(#selector(MarkdownTextView.toggleStrikethrough(_:))) }
                    .keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Code") { send(#selector(MarkdownTextView.toggleInlineCode(_:))) }
                    .keyboardShortcut("c", modifiers: [.command, .shift]) // ⌘E is "Use Selection for Find"
                Button("Math") { send(#selector(MarkdownTextView.toggleMath(_:))) }
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Link") { send(#selector(MarkdownTextView.insertMarkdownLink(_:))) }
                    .keyboardShortcut("k")
                Divider()
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { send(#selector(MarkdownTextView.setHeadingLevel(_:)), level) }
                        .keyboardShortcut(KeyEquivalent(Character("\(level)")))
                }
            }
            CommandGroup(after: .sidebar) {
                Button("Show/Hide Library") { library.toggleSidebar() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Toggle("Focus Mode", isOn: $focusMode)
                    .keyboardShortcut("d")
                Toggle("Typewriter Mode", isOn: $typewriterMode)
                    .keyboardShortcut("t")
                Divider()
                Button("Bigger Text") { fontSize = min(EditorSettings.fontSizes.upperBound, fontSize + 1) }
                    .keyboardShortcut("+")
                Button("Smaller Text") { fontSize = max(EditorSettings.fontSizes.lowerBound, fontSize - 1) }
                    .keyboardShortcut("-")
                Button("Actual Size") { fontSize = 16 }
                    .keyboardShortcut("0")
                Divider()
                Picker("Sort Notes By", selection: $library.sort) {
                    ForEach(LibrarySort.allCases) { Text($0.title).tag($0) }
                }
            }
        }

        Settings {
            SettingsView()
        }
    }

    /// Sends a formatting action to the focused editor through the responder chain.
    private func send(_ action: Selector, _ level: Int? = nil) {
        NSApp.sendAction(action, to: nil, from: level.map { NSNumber(value: $0) })
    }
}
