import SwiftUI

@main
struct PaperApp: App {
    @State private var store = DocumentStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
                .frame(minWidth: 720, minHeight: 460)
                .tint(PaperTheme.accent)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .newItem) {
                Button("New") { store.newDocument() }
                    .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) {
                Button("Open…") { store.showingImporter = true }
                    .keyboardShortcut("o", modifiers: [.command])
                Button("Save") { store.requestSave() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!store.isDirty)
            }
        }
    }
}
