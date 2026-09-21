import AppKit
import XCTest
@testable import Paper

@MainActor
final class DocumentStoreRecoveryTests: XCTestCase {
    private var directory: URL!
    private var recoveryStore: RecoveryStore!
    private var sentinel: LaunchSentinel!
    private var document: DocumentStore!
    private var coordinator: RecoveryCoordinator!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentStoreRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        recoveryStore = RecoveryStore(directory: directory)
        sentinel = LaunchSentinel(directory: directory)
        document = DocumentStore()
        coordinator = RecoveryCoordinator(store: recoveryStore, document: document)
        document.recoveryCoordinator = coordinator
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func writeFile(_ contents: String, name: String) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    private func writeCopy(
        text: String = "recovered work",
        title: String = "Notes",
        file: URL? = nil
    ) throws {
        let digest = file.flatMap { RecoveryStore.digest(ofFileAt: $0) }
        try recoveryStore.write(RecoveryPayload(
            text: text,
            title: title,
            filePath: file?.path,
            fileDigest: digest,
            lastWrittenAt: Date()
        ))
    }

    private func welcomeText() -> String {
        DocumentStore().text
    }

    // MARK: - Restore on launch

    func testCopyRestoresAsModifiedWork() throws {
        let file = try writeFile("on disk", name: "notes.txt")
        try writeCopy(text: "unsaved edits", title: "Notes", file: file)

        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(outcome, .restored(detached: false, unexpectedExit: false))
        XCTAssertEqual(document.text, "unsaved edits")
        XCTAssertEqual(document.documentTitle, "Notes")
        XCTAssertEqual(document.fileURL, file)
        XCTAssertTrue(document.isDirty)
        XCTAssertTrue(document.isRecovered)
        XCTAssertEqual(document.recoveredSourcePath, file.path)
        XCTAssertFalse(document.recoveredAfterUnexpectedExit)
    }

    func testCopyRestoresWithUnexpectedExitWordingAfterASentinel() throws {
        try writeCopy()
        sentinel.write()

        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(outcome, .restored(detached: false, unexpectedExit: true))
        XCTAssertTrue(document.isRecovered)
        XCTAssertTrue(document.recoveredAfterUnexpectedExit)
    }

    func testNoCopyLeavesTheWelcomeDocumentUntouched() throws {
        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(outcome, .nothingToRestore)
        XCTAssertEqual(document.text, welcomeText())
        XCTAssertFalse(document.isDirty)
        XCTAssertFalse(document.isRecovered)
    }

    func testUnreadableCopyOpensNormallyAndRecordsAnError() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("recovery.json"))

        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(document.text, welcomeText())
        XCTAssertFalse(document.isRecovered)
        XCTAssertNotNil(document.lastError)
        if case .restoreFailed = outcome {} else {
            XCTFail("expected restoreFailed, got \(outcome)")
        }
    }

    func testUnknownVersionCopyOpensNormallyAndRecordsAnError() throws {
        try recoveryStore.write(RecoveryPayload(
            text: "from the future",
            title: "Future",
            filePath: nil,
            fileDigest: nil,
            lastWrittenAt: Date(),
            version: RecoveryPayload.currentVersion + 1
        ))

        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(document.text, welcomeText())
        XCTAssertFalse(document.isRecovered)
        XCTAssertNotNil(document.lastError)
        if case .restoreFailed = outcome {} else {
            XCTFail("expected restoreFailed, got \(outcome)")
        }
    }

    // MARK: - The dirty-to-clean funnel

    func testRestoredDocumentSavesBackToItsOriginalFile() throws {
        let file = try writeFile("version one", name: "doc.txt")
        try writeCopy(text: "version one, edited", title: "doc", file: file)
        XCTAssertEqual(coordinator.performLaunch(sentinel: sentinel), .restored(detached: false, unexpectedExit: false))

        document.save()

        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "version one, edited")
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(recoveryStore.read(), .absent)
    }

    func testChangedUnderneathDetachesAndSaveCannotOverwrite() throws {
        let file = try writeFile("version one", name: "report.txt")
        try writeCopy(text: "unsaved edits", title: "report", file: file)
        try Data("version two, written elsewhere".utf8).write(to: file)

        let outcome = coordinator.performLaunch(sentinel: sentinel)

        XCTAssertEqual(outcome, .restored(detached: true, unexpectedExit: false))
        XCTAssertNil(document.fileURL, "must not stay attached to a changed file")
        XCTAssertTrue(document.isRecovered)
        XCTAssertEqual(document.recoveredSourcePath, file.path)

        document.save()

        XCTAssertTrue(document.showingExporter, "a detached document must ask for a destination")
        XCTAssertEqual(
            try String(contentsOf: file, encoding: .utf8),
            "version two, written elsewhere",
            "the newer file must survive"
        )
    }

    func testChangedWhileOpenDetachesOnSave() throws {
        let file = try writeFile("version one", name: "live.txt")
        try writeCopy(text: "unsaved edits", title: "live", file: file)
        XCTAssertEqual(
            coordinator.performLaunch(sentinel: sentinel),
            .restored(detached: false, unexpectedExit: false)
        )
        XCTAssertEqual(document.fileURL, file)

        try Data("version two, written elsewhere".utf8).write(to: file)
        document.textDidChange("unsaved edits, more")
        document.save()

        XCTAssertNil(document.fileURL)
        XCTAssertTrue(document.showingExporter)
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "version two, written elsewhere")
    }

    func testExporterPathDiscardsTheCopy(AE2 _: Bool = false) throws {
        document.textDidChange("to be saved elsewhere")
        coordinator.tick()
        XCTAssertNotEqual(recoveryStore.read(), .absent)

        let target = directory.appendingPathComponent("saved.txt")
        document.savedViaExporter(to: target)

        XCTAssertEqual(document.fileURL, target)
        XCTAssertFalse(document.isDirty)
        XCTAssertEqual(recoveryStore.read(), .absent)
    }

    func testNewDocumentCancelsPendingCaptureAndDiscards() async throws {
        document.textDidChange("abandoned")
        coordinator.tick()
        XCTAssertNotEqual(recoveryStore.read(), .absent)

        document.textDidChange("about to vanish")
        coordinator.noteEdited()
        XCTAssertTrue(coordinator.hasPendingCapture)

        document.newDocument()

        XCTAssertFalse(coordinator.hasPendingCapture)
        await coordinator.waitForPendingCapture()
        XCTAssertEqual(recoveryStore.read(), .absent)
        XCTAssertEqual(document.text, "")
    }

    func testOpenCancelsPendingCaptureAndDiscards() async throws {
        let file = try writeFile("file contents", name: "opened.txt")
        document.textDidChange("abandoned")
        coordinator.tick()
        XCTAssertNotEqual(recoveryStore.read(), .absent)

        document.textDidChange("about to vanish")
        coordinator.noteEdited()
        XCTAssertTrue(coordinator.hasPendingCapture)

        document.open(url: file)

        XCTAssertFalse(coordinator.hasPendingCapture)
        await coordinator.waitForPendingCapture()
        XCTAssertEqual(recoveryStore.read(), .absent)
        XCTAssertEqual(document.text, "file contents")
        XCTAssertFalse(document.isDirty)
    }

    // MARK: - Second instance and termination

    func testSecondInstanceRestoresNothing() throws {
        // A directory no other coordinator in this test holds.
        let dir = directory.appendingPathComponent("second-instance", isDirectory: true)
        let storeA = RecoveryStore(directory: dir)
        let sentinelA = LaunchSentinel(directory: dir)
        let firstDocument = DocumentStore()
        let first = RecoveryCoordinator(store: storeA, document: firstDocument)
        XCTAssertTrue(first.isOwner)
        try storeA.write(RecoveryPayload(
            text: "first instance work",
            title: "Notes",
            filePath: nil,
            fileDigest: nil,
            lastWrittenAt: Date()
        ))

        let secondDocument = DocumentStore()
        let second = RecoveryCoordinator(store: storeA, document: secondDocument)
        secondDocument.recoveryCoordinator = second

        let outcome = second.performLaunch(sentinel: sentinelA)

        XCTAssertFalse(second.isOwner)
        XCTAssertNotNil(second.blockedReason)
        XCTAssertEqual(outcome, .ownedElsewhere)
        XCTAssertEqual(secondDocument.text, welcomeText())
        XCTAssertFalse(secondDocument.isRecovered)
        _ = first
    }

    func testTerminationFlushesTheFinalCaptureThenRemovesTheSentinel() throws {
        sentinel.write()
        document.textDidChange("unsaved at quit")
        // The debounced capture has not fired; termination must flush it.

        let delegate = AppDelegate()
        delegate.coordinator = coordinator
        delegate.sentinel = sentinel
        delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))

        guard case let .present(copy) = recoveryStore.read() else {
            return XCTFail("termination must flush the final capture")
        }
        XCTAssertEqual(copy.text, "unsaved at quit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentinel.url.path))
    }
}
