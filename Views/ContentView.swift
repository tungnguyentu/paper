import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: DocumentStore

    var body: some View {
        EditorView(store: store)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    DocumentTitle(store: store)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: store.requestSave) {
                        Label("Save", systemImage: "tray.and.arrow.down")
                    }
                    .labelStyle(.iconOnly)
                    .help("Save")
                    .disabled(!store.isDirty)

                    Menu {
                        Button("New Document", systemImage: "doc.badge.plus", action: store.newDocument)
                        Button("Open…", systemImage: "folder") { store.showingImporter = true }
                        Divider()
                        Button("Save As…", systemImage: "square.and.arrow.down") {
                            store.showingExporter = true
                        }
                        if store.isRecovered {
                            Divider()
                            Button("Discard Recovered Work…", systemImage: "trash", role: .destructive) {
                                store.showingDiscardConfirmation = true
                            }
                        }
                    } label: {
                        Label("More document actions", systemImage: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                }
            }
            .fileImporter(isPresented: $store.showingImporter, allowedContentTypes: [.plainText]) { result in
                if case let .success(url) = result { store.open(url: url) }
            }
            .fileExporter(
                isPresented: $store.showingExporter,
                document: PlainTextDocument(text: store.text),
                contentType: .plainText,
                defaultFilename: store.title
            ) { result in
                if case let .success(url) = result {
                    store.savedViaExporter(to: url)
                }
            }
            .alert("Paper", isPresented: Binding(
                get: { store.lastError != nil },
                set: { if !$0 { store.lastError = nil } }
            )) {
                Button("OK", role: .cancel) { store.lastError = nil }
            } message: {
                Text(store.lastError ?? "")
            }
            .alert(
                "Discard recovered work?",
                isPresented: $store.showingDiscardConfirmation
            ) {
                Button("Discard", role: .destructive) { store.discardRecoveredWork() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The recovered text and its recovery copy will be permanently deleted. This cannot be undone.")
            }
    }
}

private struct DocumentTitle: View {
    @Bindable var store: DocumentStore
    @State private var draftTitle = ""
    @State private var isRenaming = false
    @State private var isHovering = false
    @FocusState private var titleFieldIsFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Document title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(minWidth: 180, maxWidth: 280)
                    .focused($titleFieldIsFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
                Button(action: beginRename) {
                    VStack(spacing: 1) {
                        HStack(spacing: 5) {
                            Text(store.title)
                                .font(.headline)
                                .lineLimit(1)
                            if store.isDirty {
                                Circle()
                                    .fill(.secondary)
                                    .frame(width: 5, height: 5)
                                    .accessibilityLabel("Modified")
                            }
                            if store.isRecovered {
                                Image(systemName: "arrow.uturn.backward.circle")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("Recovered")
                                    .help("Recovered unsaved work")
                            }
                            Image(systemName: "pencil")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .opacity(isHovering ? 1 : 0)
                        }
                        Text(store.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(nsColor: .quaternaryLabelColor).opacity(isHovering ? 0.5 : 0))
                    }
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help("Rename document")
                .accessibilityHint("Click to rename")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let base = "\(store.title), \(store.subtitle)"
        let recovered = store.isRecovered ? ", recovered unsaved work" : ""
        return store.isDirty ? "\(base)\(recovered), modified" : "\(base)\(recovered)"
    }

    private func beginRename() {
        draftTitle = store.title
        isRenaming = true
        DispatchQueue.main.async { titleFieldIsFocused = true }
    }

    private func commitRename() {
        store.renameDocument(to: draftTitle)
        isRenaming = false
    }

    private func cancelRename() {
        isRenaming = false
    }
}

struct PlainTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
