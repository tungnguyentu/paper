import SwiftUI

/// Handles graceful termination: flushes one final recovery capture, then
/// removes the clean-exit sentinel, in that order.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var coordinator: RecoveryCoordinator?
    var sentinel: LaunchSentinel?

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.captureNow()
        sentinel?.remove()
    }
}

@main
struct PaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate
    @State private var store: DocumentStore
    private let coordinator: RecoveryCoordinator

    init() {
        let directory = RecoveryStore.defaultDirectory()
        let recoveryStore = RecoveryStore(directory: directory)
        let sentinel = LaunchSentinel(directory: directory)
        let store = DocumentStore()
        let coordinator = RecoveryCoordinator(store: recoveryStore, document: store)
        store.recoveryCoordinator = coordinator
        // Restore synchronously, before the body builds the first window, so
        // no window flashes the welcome text and is then replaced.
        _ = coordinator.performLaunch(sentinel: sentinel)
        coordinator.start()
        self._store = State(initialValue: store)
        self.coordinator = coordinator
        appDelegate.coordinator = coordinator
        appDelegate.sentinel = sentinel
    }

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
