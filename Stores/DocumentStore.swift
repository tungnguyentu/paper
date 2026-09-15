import Foundation
import Observation

@MainActor
@Observable
final class DocumentStore {
    var text = ""
    var fileURL: URL?
    var documentTitle = "Untitled Document"
    var isDirty = false
    var cursorLine = 1
    var showingImporter = false
    var showingExporter = false
    var lastError: String?

    init() {
        text = "Welcome to Paper\n\nA straightforward place to write. Open a text file or simply start typing."
    }

    var title: String { documentTitle }
    var subtitle: String { fileURL?.lastPathComponent ?? "Not saved yet" }
    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var lineCount: Int { max(text.components(separatedBy: .newlines).count, 1) }

    func newDocument() {
        text = ""
        fileURL = nil
        documentTitle = "Untitled Document"
        isDirty = false
        cursorLine = 1
    }

    func textDidChange(_ newText: String) {
        text = newText
        isDirty = true
    }

    func open(url: URL) {
        do {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            documentTitle = url.deletingPathExtension().lastPathComponent
            isDirty = false
            cursorLine = 1
        } catch {
            lastError = "Couldn’t open \(url.lastPathComponent)."
        }
    }

    func save(to url: URL? = nil) {
        let destination = url ?? fileURL
        guard let destination else {
            showingExporter = true
            return
        }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            fileURL = destination
            isDirty = false
        } catch {
            lastError = "Couldn’t save \(destination.lastPathComponent)."
        }
    }

    func requestSave() { save() }

    func renameDocument(to newTitle: String) {
        let cleanedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        documentTitle = cleanedTitle
        isDirty = true
    }

    func updateCursorLine(_ line: Int) {
        cursorLine = max(line, 1)
    }
}
