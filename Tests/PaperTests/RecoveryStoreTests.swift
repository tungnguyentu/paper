import XCTest
@testable import Paper

final class RecoveryStoreTests: XCTestCase {
    private var directory: URL!
    private var store: RecoveryStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecoveryStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = RecoveryStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try? FileManager.default.removeItem(at: directory)
    }

    private func payload(
        text: String = "hello",
        title: String = "Untitled Document",
        filePath: String? = nil,
        fileDigest: String? = nil,
        lastWrittenAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> RecoveryPayload {
        RecoveryPayload(
            text: text,
            title: title,
            filePath: filePath,
            fileDigest: fileDigest,
            lastWrittenAt: lastWrittenAt
        )
    }

    // MARK: - Round trip

    func testRoundTripPreservesEveryField() throws {
        let original = payload(
            text: "some text\nand more",
            title: "My Notes",
            filePath: "/tmp/notes.txt",
            fileDigest: "abc123"
        )
        try store.write(original)

        guard case let .present(restored) = store.read() else {
            return XCTFail("expected a present payload, got \(store.read())")
        }
        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.version, RecoveryPayload.currentVersion)
    }

    func testUntitledPayloadReadsBackAsUntitled() throws {
        try store.write(payload(filePath: nil, fileDigest: nil))

        guard case let .present(restored) = store.read() else {
            return XCTFail("expected a present payload")
        }
        XCTAssertNil(restored.filePath)
        XCTAssertNil(restored.fileDigest)
    }

    // MARK: - Atomic replace

    func testWritingTwiceLeavesOnlyTheNewerCopy() throws {
        try store.write(payload(text: "first"))
        try store.write(payload(text: "second"))

        guard case let .present(restored) = store.read() else {
            return XCTFail("expected a present payload")
        }
        XCTAssertEqual(restored.text, "second")

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertEqual(leftovers, ["recovery.json"], "an atomic write should leave no temporary file behind")
    }

    func testFailedWriteLeavesThePreviousCopyIntact() throws {
        try store.write(payload(text: "precious"))

        // Make the directory unwritable so the replacement cannot land.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        XCTAssertThrowsError(try store.write(payload(text: "clobbered")))

        guard case let .present(restored) = store.read() else {
            return XCTFail("expected the previous copy to survive")
        }
        XCTAssertEqual(restored.text, "precious")
    }

    // MARK: - Read outcomes

    func testReadingWithNothingOnDiskReportsAbsent() {
        XCTAssertEqual(store.read(), .absent)
    }

    func testCorruptCopyReportsUnreadableNotAbsent() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("recovery.json"))

        guard case .unreadable = store.read() else {
            return XCTFail("expected unreadable, got \(store.read())")
        }
    }

    func testFutureVersionReportsUnsupportedRatherThanCorrupt() throws {
        try store.write(payload(text: "from the future"))
        // Rewrite with a version this build does not know.
        let data = try Data(contentsOf: directory.appendingPathComponent("recovery.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["version"] = RecoveryPayload.currentVersion + 1
        try JSONSerialization.data(withJSONObject: object)
            .write(to: directory.appendingPathComponent("recovery.json"))

        XCTAssertEqual(store.read(), .unsupportedVersion(RecoveryPayload.currentVersion + 1))
    }

    // MARK: - Discard

    func testDiscardRemovesTheCopy() throws {
        try store.write(payload())
        try store.discard()

        XCTAssertEqual(store.read(), .absent)
    }

    func testDiscardWithNothingToDiscardIsNotAnError() {
        XCTAssertNoThrow(try store.discard())
    }

    // MARK: - Source-file digest

    private func writeFile(_ contents: String, name: String = "source.txt") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func testDigestMatchesForAnUnchangedFile() throws {
        let file = try writeFile("original contents")
        let digest = try XCTUnwrap(RecoveryStore.digest(ofFileAt: file))

        let result = store.fileMatch(for: payload(filePath: file.path, fileDigest: digest))

        XCTAssertEqual(result, .matches)
    }

    func testDigestDiffersWhenBytesChangeAtTheSameSizeAndModificationTime() throws {
        let file = try writeFile("AAAA")
        let digest = try XCTUnwrap(RecoveryStore.digest(ofFileAt: file))
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)

        try Data("BBBB".utf8).write(to: file)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: file.path)

        XCTAssertEqual(
            store.fileMatch(for: payload(filePath: file.path, fileDigest: digest)),
            .differs,
            "a same-size edit with preserved metadata must still be detected"
        )
    }

    func testDigestMatchesAgainWhenContentIsRestored() throws {
        let file = try writeFile("original")
        let digest = try XCTUnwrap(RecoveryStore.digest(ofFileAt: file))

        try Data("changed".utf8).write(to: file)
        XCTAssertEqual(store.fileMatch(for: payload(filePath: file.path, fileDigest: digest)), .differs)

        try Data("original".utf8).write(to: file)
        XCTAssertEqual(store.fileMatch(for: payload(filePath: file.path, fileDigest: digest)), .matches)
    }

    func testMissingFileReportsMissing() {
        let result = store.fileMatch(
            for: payload(filePath: directory.appendingPathComponent("gone.txt").path, fileDigest: "abc")
        )

        XCTAssertEqual(result, .missing)
    }

    func testNotFileBackedReportsNotFileBacked() {
        XCTAssertEqual(store.fileMatch(for: payload(filePath: nil, fileDigest: nil)), .notFileBacked)
    }
}
