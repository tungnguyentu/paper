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

    /// The recovery coordinator, owned by the app. Weak to avoid a retain
    /// cycle: the coordinator already holds this store.
    weak var recoveryCoordinator: RecoveryCoordinator?

    /// Whether this document was restored from a recovery copy at launch.
    private(set) var isRecovered = false
    /// The file the recovered work came from, whether or not it stayed
    /// attached. Nil unless the document was recovered.
    private(set) var recoveredSourcePath: String?
    /// Whether the previous session ended without removing its sentinel.
    /// Drives the restore notice's wording only.
    private(set) var recoveredAfterUnexpectedExit = false

    /// Whether the recovery notice was dismissed. Dismissing hides the notice
    /// without discarding the recovered work.
    var recoveryNoticeDismissed = false
    /// Whether the recovery announcement was already posted, so it is spoken
    /// once no matter how many windows render the notice.
    var recoveryAnnouncementPosted = false
    /// Whether the discard confirmation is presented. Separate from the
    /// error alert so the two can never race the same presentation.
    var showingDiscardConfirmation = false

    init() {
        text = "Welcome to Paper\n\nA straightforward place to write. Open a text file or simply start typing."
    }

    var title: String { documentTitle }
    var subtitle: String {
        if let fileURL {
            return fileURL.lastPathComponent
        }
        // A detached recovery still came from somewhere; say so, so the user
        // does not mistake it for an ordinary unsaved edit.
        if isRecovered, let source = recoveredSourcePath {
            return "Recovered from \(URL(fileURLWithPath: source).lastPathComponent)"
        }
        return "Not saved yet"
    }
    var wordCount: Int { text.split { $0.isWhitespace || $0.isNewline }.count }
    var lineCount: Int { max(text.components(separatedBy: .newlines).count, 1) }

    func newDocument() {
        text = ""
        fileURL = nil
        documentTitle = "Untitled Document"
        cursorLine = 1
        recoveryCoordinator?.noteAttachedToFile(nil)
        clearModifiedFlag(discardingRecovery: true)
    }

    func textDidChange(_ newText: String) {
        text = newText
        isDirty = true
        recoveryCoordinator?.noteEdited()
    }

    func open(url: URL) {
        do {
            let accessGranted = url.startAccessingSecurityScopedResource()
            defer { if accessGranted { url.stopAccessingSecurityScopedResource() } }
            text = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            documentTitle = url.deletingPathExtension().lastPathComponent
            cursorLine = 1
            recoveryCoordinator?.noteAttachedToFile(url)
            clearModifiedFlag(discardingRecovery: true)
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
        if destination == fileURL,
           let recorded = recoveryCoordinator?.recordedDigest(forPath: destination.path),
           RecoveryStore.digest(ofFileAt: destination) != recorded
        {
            // The file changed on disk since this document was attached to it.
            // Detach rather than overwrite, and require the user to choose a
            // destination.
            fileURL = nil
            recoveryCoordinator?.noteAttachedToFile(nil)
            lastError = "“\(destination.lastPathComponent)” changed on disk. The document was detached to protect it — choose where to save."
            showingExporter = true
            return
        }
        do {
            try text.write(to: destination, atomically: true, encoding: .utf8)
            fileURL = destination
            recoveryCoordinator?.noteAttachedToFile(destination)
            clearModifiedFlag(discardingRecovery: true)
        } catch {
            lastError = "Couldn’t save \(destination.lastPathComponent)."
        }
    }

    /// Called when the Save As exporter completes. Carries the same recovery
    /// semantics as `save()`: the previously open document is replaced, so
    /// its copy is discarded.
    func savedViaExporter(to url: URL) {
        fileURL = url
        documentTitle = url.deletingPathExtension().lastPathComponent
        recoveryCoordinator?.noteAttachedToFile(url)
        clearModifiedFlag(discardingRecovery: true)
    }

    /// Discards recovered work deliberately: clears the copy and returns the
    /// document to a fresh state.
    func discardRecoveredWork() {
        newDocument()
        recoveryNoticeDismissed = true
    }

    /// Applies a recovery payload at launch. Attaches to the recorded file
    /// only when it still matches; otherwise presents the work detached from
    /// that path. Returns whether the restored work was detached.
    @discardableResult
    func applyRecoveryPayload(
        _ payload: RecoveryPayload,
        checkingWith recoveryStore: RecoveryStore,
        unexpectedExit: Bool
    ) -> Bool {
        text = payload.text
        documentTitle = payload.title
        cursorLine = 1
        let detached: Bool
        switch recoveryStore.fileMatch(for: payload) {
        case .notFileBacked:
            fileURL = nil
            detached = false
        case .matches:
            fileURL = payload.filePath.map(URL.init(fileURLWithPath:))
            detached = false
        case .differs, .missing:
            fileURL = nil
            detached = true
        }
        isDirty = true
        isRecovered = true
        recoveredSourcePath = payload.filePath
        recoveredAfterUnexpectedExit = unexpectedExit
        recoveryNoticeDismissed = false
        recoveryAnnouncementPosted = false
        recoveryCoordinator?.noteAttachedToFile(fileURL)
        return detached
    }

    /// The single path through which the document may become clean. Every
    /// caller names whether the recovery copy goes with it, so no path that
    /// clears the flag can strand a copy on disk.
    private func clearModifiedFlag(discardingRecovery: Bool) {
        isDirty = false
        isRecovered = false
        recoveredSourcePath = nil
        recoveredAfterUnexpectedExit = false
        if discardingRecovery {
            recoveryCoordinator?.noteCleaned()
        }
    }

    func requestSave() { save() }

    func renameDocument(to newTitle: String) {
        let cleanedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedTitle.isEmpty else { return }
        documentTitle = cleanedTitle
        isDirty = true
        recoveryCoordinator?.noteEdited()
    }

    func updateCursorLine(_ line: Int) {
        cursorLine = max(line, 1)
    }
}
