import XCTest
@testable import Paper

/// Store-level behaviour behind the recovery surface: the notice predicate,
/// the discard action, failure surfacing, and the recovered subtitle.
/// Layout, focus, and appearance are verified by screenshot.
@MainActor
final class RecoverySurfaceTests: XCTestCase {
    private var directory: URL!
    private var recoveryStore: RecoveryStore!
    private var sentinel: LaunchSentinel!
    private var document: DocumentStore!
    private var coordinator: RecoveryCoordinator!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoverySurfaceTests-\(UUID().uuidString)", isDirectory: true)
        recoveryStore = RecoveryStore(directory: directory)
        sentinel = LaunchSentinel(directory: directory)
        document = DocumentStore()
        coordinator = RecoveryCoordinator(store: recoveryStore, document: document)
        document.recoveryCoordinator = coordinator
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeCopy(text: String = "recovered", title: String = "Notes", file: URL? = nil) throws {
        let digest = file.flatMap { RecoveryStore.digest(ofFileAt: $0) }
        try recoveryStore.write(RecoveryPayload(
            text: text,
            title: title,
            filePath: file?.path,
            fileDigest: digest,
            lastWrittenAt: Date()
        ))
    }

    private func writeFile(_ contents: String, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// The inputs the notice predicate reads.
    private func noticeShouldShow(for store: DocumentStore) -> Bool {
        store.isRecovered && !store.recoveryNoticeDismissed
    }

    // MARK: - Notice state

    func testRestoredDocumentShowsTheNotice() throws {
        try writeCopy()

        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: false, unexpectedExit: false))
        XCTAssertTrue(noticeShouldShow(for: document))
    }

    func testNormalLaunchHasNothingToShow() throws {
        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .nothingToRestore)
        XCTAssertFalse(noticeShouldShow(for: document))
    }

    func testDismissingTheNoticeLeavesEverythingIntact() throws {
        try writeCopy(text: "keep me")
        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: false, unexpectedExit: false))

        document.recoveryNoticeDismissed = true

        XCTAssertFalse(noticeShouldShow(for: document))
        XCTAssertEqual(document.text, "keep me")
        XCTAssertTrue(document.isDirty)
        XCTAssertTrue(document.isRecovered)
        guard case .present = recoveryStore.read() else {
            return XCTFail("dismissing must not discard the copy")
        }
    }

    // MARK: - Discard

    func testDiscardClearsEverythingAndTheNextLaunchIsClean() throws {
        try writeCopy(text: "doomed work")
        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: false, unexpectedExit: false))

        document.discardRecoveredWork()

        XCTAssertEqual(document.text, "")
        XCTAssertFalse(document.isDirty)
        XCTAssertFalse(document.isRecovered)
        XCTAssertEqual(recoveryStore.read(), .absent)

        // Release the lock so a fresh launch can take ownership.
        document.recoveryCoordinator = nil
        coordinator = nil
        let nextDocument = DocumentStore()
        coordinator = RecoveryCoordinator(store: recoveryStore, document: nextDocument)
        nextDocument.recoveryCoordinator = coordinator

        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .nothingToRestore)
        XCTAssertFalse(noticeShouldShow(for: nextDocument))
    }

    // MARK: - Failure surfacing

    func testCaptureFailureSurfacesToTheDocumentOnce() async throws {
        // Break the directory after ownership is taken.
        try? FileManager.default.removeItem(at: directory)
        FileManager.default.createFile(atPath: directory.path, contents: nil)

        document.textDidChange("doomed")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        XCTAssertNotNil(document.lastError, "the first failure must reach the document")

        document.lastError = nil
        document.textDidChange("doomed again")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        XCTAssertNil(document.lastError, "repeat failures must not re-alert")
        XCTAssertNotNil(coordinator.lastError, "the coordinator must still track the failure")
    }

    // MARK: - Recovered subtitle

    func testDetachedSubtitleNamesTheSourceFile() throws {
        let file = try writeFile("version one", name: "report.txt")
        try writeCopy(text: "unsaved edits", title: "report", file: file)
        try Data("version two".utf8).write(to: file)

        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: true, unexpectedExit: false))

        XCTAssertEqual(document.subtitle, "Recovered from report.txt")
    }

    func testAttachedSubtitleKeepsTheFilename() throws {
        let file = try writeFile("version one", name: "notes.txt")
        try writeCopy(text: "unsaved edits", title: "notes", file: file)

        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: false, unexpectedExit: false))

        XCTAssertEqual(document.subtitle, "notes.txt")
    }
}
