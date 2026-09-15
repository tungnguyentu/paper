import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: DocumentStore

    var body: some View {
        EditorView(store: store)
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button(action: store.newDocument) {
                        Image(systemName: "plus")
                    }
                    .help("New Document")
                    .accessibilityLabel("New Document")

                    Button(action: { store.showingImporter = true }) {
                        Image(systemName: "folder")
                    }
                    .help("Open Text File")
                    .accessibilityLabel("Open Text File")
                }

                ToolbarItem(placement: .principal) {
                    DocumentTitle(store: store)
                }

                ToolbarItemGroup(placement: .primaryAction) {
                    Button(action: store.requestSave) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save")
                    .accessibilityLabel("Save")
                    .disabled(!store.isDirty && store.fileURL != nil)

                    Menu {
                        Button("New Document", action: store.newDocument)
                        Button("Open…") { store.showingImporter = true }
                        Divider()
                        Button("Save As…") { store.showingExporter = true }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("More document actions")
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
                    store.fileURL = url
                    store.documentTitle = url.deletingPathExtension().lastPathComponent
                    store.isDirty = false
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
    }
}

private struct DocumentTitle: View {
    @Bindable var store: DocumentStore
    @State private var draftTitle = ""
    @State private var isRenaming = false
    @FocusState private var titleFieldIsFocused: Bool

    var body: some View {
        Group {
            if isRenaming {
                TextField("Document title", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                    .frame(width: 220)
                    .focused($titleFieldIsFocused)
                    .onSubmit(commitRename)
                    .onExitCommand(perform: cancelRename)
            } else {
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
                }
                .onTapGesture(count: 2, perform: beginRename)
                .accessibilityHint("Double-click to rename")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(store.isDirty ? "\(store.title), modified" : store.title)
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
