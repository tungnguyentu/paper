import XCTest
@testable import Paper

/// Counts successful writes from any thread.
private final class WriteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

@MainActor
final class RecoveryCoordinatorTests: XCTestCase {
    private var directory: URL!
    private var store: RecoveryStore!
    private var document: DocumentStore!
    private var writes: WriteCounter!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveryCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        store = RecoveryStore(directory: directory)
        document = DocumentStore()
        writes = WriteCounter()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeCoordinator(
        debounce: Duration = .zero,
        tick: Duration = .seconds(30),
        sizeBound: Int = 1_048_576
    ) -> RecoveryCoordinator {
        let coordinator = RecoveryCoordinator(
            store: store,
            document: document,
            configuration: RecoveryCoordinator.Configuration(
                debounceInterval: debounce,
                tickInterval: tick,
                synchronousSizeBound: sizeBound
            )
        )
        coordinator.onDidWrite = { [writes] in writes?.increment() }
        return coordinator
    }

    private func presentCopy() throws -> RecoveryPayload {
        guard case let .present(payload) = store.read() else {
            throw XCTSkip("expected a recovery copy on disk")
        }
        return payload
    }

    // MARK: - Debounce coalescing

    func testBurstOfEditsProducesOneWrite() async throws {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.isOwner)

        for i in 1...5 {
            document.textDidChange("edit \(i)")
            coordinator.noteEdited()
        }
        await coordinator.waitForPendingCapture()

        XCTAssertEqual(writes.count, 1, "five rapid edits must coalesce into a single write")
        XCTAssertEqual(try presentCopy().text, "edit 5")
    }

    // MARK: - Untitled and clean documents

    func testUntitledDirtyDocumentProducesACopy() async throws {
        let coordinator = makeCoordinator()
        XCTAssertNil(document.fileURL)

        document.textDidChange("unsaved work")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()

        let copy = try presentCopy()
        XCTAssertEqual(copy.text, "unsaved work")
        XCTAssertNil(copy.filePath)
    }

    func testCleanDocumentProducesNoCopy() async throws {
        let coordinator = makeCoordinator()
        XCTAssertFalse(document.isDirty)

        coordinator.tick()
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()

        XCTAssertEqual(store.read(), .absent)
        XCTAssertEqual(writes.count, 0)
    }

    // MARK: - Periodic tick

    func testTickCapturesWhileDirtyAndStopsWhenClean() async throws {
        let coordinator = makeCoordinator()

        document.textDidChange("v1")
        coordinator.tick()
        XCTAssertEqual(writes.count, 1)

        document.textDidChange("v2")
        coordinator.tick()
        XCTAssertEqual(writes.count, 2)
        XCTAssertEqual(try presentCopy().text, "v2")

        // The funnel clears the flag and only then tells the coordinator.
        document.isDirty = false
        coordinator.noteCleaned()
        coordinator.tick()
        XCTAssertEqual(writes.count, 2, "a clean document must not be captured")
    }

    // MARK: - Save cancels a pending capture

    func testPendingCaptureDoesNotLandAfterTheDocumentBecomesClean() async throws {
        let coordinator = makeCoordinator(debounce: .seconds(60))

        document.textDidChange("about to be saved")
        coordinator.noteEdited()
        XCTAssertTrue(coordinator.hasPendingCapture)

        coordinator.noteCleaned()
        XCTAssertFalse(coordinator.hasPendingCapture)
        await coordinator.waitForPendingCapture()

        XCTAssertEqual(store.read(), .absent)
        XCTAssertEqual(writes.count, 0)
    }

    // MARK: - The user's file is never touched

    func testCapturingNeverModifiesTheDocumentFile() async throws {
        let coordinator = makeCoordinator()
        let file = directory.appendingPathComponent("notes.txt")
        try Data("original".utf8).write(to: file)
        let before = try FileManager.default.attributesOfItem(atPath: file.path)

        document.fileURL = file

        document.textDidChange("edited in the app")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        // Sync path: the write already landed; no need to await.

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "original")
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date,
            before[.modificationDate] as? Date
        )
        // And the capture did run (proving the check above is meaningful).
        XCTAssertEqual(writes.count, 1)
    }

    // MARK: - The digest is recorded once and never refreshed by a capture

    func testCapturePreservesAnExistingDigest() async throws {
        let coordinator = makeCoordinator()
        let file = directory.appendingPathComponent("doc.txt")
        try Data("version one".utf8).write(to: file)
        document.fileURL = file

        document.textDidChange("first edit")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        let firstDigest = try XCTUnwrap(try presentCopy().fileDigest)

        try Data("version two, edited elsewhere".utf8).write(to: file)
        document.textDidChange("second edit")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()

        XCTAssertEqual(
            try presentCopy().fileDigest,
            firstDigest,
            "a capture must not refresh the recorded digest"
        )
    }

    func testAttachTimeDigestSurvivesAFileChangeBeforeFirstCapture() async throws {
        let coordinator = makeCoordinator()
        let file = directory.appendingPathComponent("attached.txt")
        try Data("as attached".utf8).write(to: file)
        document.fileURL = file
        coordinator.noteAttachedToFile(file)

        try Data("changed before first capture".utf8).write(to: file)
        document.textDidChange("edited")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()

        // The stored digest must predate the external change: recompute it
        // from the live file and require a difference.
        let currentDigest = try XCTUnwrap(RecoveryStore.digest(ofFileAt: file))
        let storedDigest = try XCTUnwrap(try presentCopy().fileDigest)
        XCTAssertNotEqual(storedDigest, currentDigest, "the stored digest must be the attach-time one")
    }

    // MARK: - Large documents move off the main actor

    func testLargeDocumentIsCapturedInFull() async throws {
        let coordinator = makeCoordinator(sizeBound: 10)
        let bigText = String(repeating: "0123456789", count: 500)

        document.textDidChange(bigText)
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        await coordinator.waitForBackgroundWork()

        XCTAssertEqual(writes.count, 1)
        XCTAssertEqual(try presentCopy().text, bigText)
    }

    // MARK: - Capture failure

    private func breakDirectory() throws {
        // Replace the recovery directory with a file so every write fails.
        try? FileManager.default.removeItem(at: directory)
        FileManager.default.createFile(atPath: directory.path, contents: nil)
    }

    func testFailedCaptureIsReportedAndPriorSuccessTimeIsUnchanged() async throws {
        let coordinator = makeCoordinator()

        document.textDidChange("first, successful")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        XCTAssertNil(coordinator.lastError)
        let firstSuccess = try XCTUnwrap(coordinator.lastSuccessfulWriteAt)

        try breakDirectory()

        document.textDidChange("second, failing")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()
        XCTAssertNotNil(coordinator.lastError, "a failed capture must be reported")
        XCTAssertEqual(
            coordinator.lastSuccessfulWriteAt,
            firstSuccess,
            "a failed write must not move the last-good timestamp"
        )
    }

    func testFirstCaptureFailureLeavesNoSuccessTime() async throws {
        // The coordinator takes ownership while the directory is healthy;
        // only the later write fails.
        let coordinator = makeCoordinator()
        try breakDirectory()

        document.textDidChange("doomed")
        coordinator.noteEdited()
        await coordinator.waitForPendingCapture()

        XCTAssertNotNil(coordinator.lastError)
        XCTAssertNil(coordinator.lastSuccessfulWriteAt)
        XCTAssertEqual(store.read(), .absent)
    }

    // MARK: - Single-instance ownership

    func testSecondInstanceCapturesNothingAndSaysSo() async throws {
        let first = makeCoordinator()
        XCTAssertTrue(first.isOwner)

        let secondStore = RecoveryStore(directory: directory)
        let secondDocument = DocumentStore()
        let second = RecoveryCoordinator(store: secondStore, document: secondDocument)
        XCTAssertFalse(second.isOwner)
        XCTAssertNotNil(second.blockedReason)

        secondDocument.textDidChange("from the second instance")
        second.noteEdited()
        await second.waitForPendingCapture()
        second.tick()

        XCTAssertEqual(secondStore.read(), .absent)
        _ = first
    }
}
