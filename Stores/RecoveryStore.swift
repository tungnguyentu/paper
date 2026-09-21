import CryptoKit
import Foundation

/// The recovery copy of one in-progress document.
///
/// Written continuously while the document has unsaved changes, and read at
/// launch. It carries the document text plus the identity needed to restore
/// it: the title, the file it came from when it had one, a digest of that
/// file, and when the copy was last written.
struct RecoveryPayload: Codable, Equatable {
    /// Bumped when the payload's shape changes. A reader that does not know a
    /// version reports it rather than treating the copy as corrupt, so a
    /// future build cannot silently discard recoverable work.
    static let currentVersion = 1

    var version: Int
    var text: String
    var title: String
    /// `nil` when the document has never been saved to a file.
    var filePath: String?
    /// Digest of the source file taken when the document was attached to it.
    /// Deliberately never refreshed by a capture: a refreshed digest would
    /// absorb an external change and defeat the check it exists for.
    var fileDigest: String?
    /// When this copy was last written successfully, so a failed capture can
    /// tell the user how far behind the copy on disk is.
    var lastWrittenAt: Date

    init(
        text: String,
        title: String,
        filePath: String?,
        fileDigest: String?,
        lastWrittenAt: Date,
        version: Int = RecoveryPayload.currentVersion
    ) {
        self.version = version
        self.text = text
        self.title = title
        self.filePath = filePath
        self.fileDigest = fileDigest
        self.lastWrittenAt = lastWrittenAt
    }
}

/// What is on disk for this document's recovery copy.
enum RecoveryReadResult: Equatable {
    case absent
    case unreadable(String)
    case unsupportedVersion(Int)
    case present(RecoveryPayload)
}

/// How a payload's recorded digest compares with the file it came from.
enum RecoveryFileMatch: Equatable {
    case notFileBacked
    case matches
    case differs
    /// The file is gone, or could not be read. Treated as "detach", which is
    /// the safe direction.
    case missing
}

/// Reads and writes the single recovery copy for the in-progress document.
struct RecoveryStore {
    let directory: URL

    private var copyURL: URL { directory.appendingPathComponent("recovery.json") }

    init(directory: URL) {
        self.directory = directory
    }

    /// `Application Support/<bundle id>/recovery`, falling back to a fixed
    /// folder name when there is no bundle identifier, so running the bare
    /// binary or the test bundle never writes into the real app's directory.
    static func defaultDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Paper", isDirectory: true)
            .appendingPathComponent("recovery", isDirectory: true)
    }

    /// Writes the copy, creating the directory if needed.
    ///
    /// `.atomic` writes a temporary file and renames it into place, so an
    /// interrupted write leaves the previous copy intact rather than a
    /// half-written hybrid.
    func write(_ payload: RecoveryPayload) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder().encode(payload)
        try data.write(to: copyURL, options: .atomic)
    }

    func read() -> RecoveryReadResult {
        guard FileManager.default.fileExists(atPath: copyURL.path) else { return .absent }
        do {
            let data = try Data(contentsOf: copyURL)
            let payload = try JSONDecoder().decode(RecoveryPayload.self, from: data)
            guard payload.version == RecoveryPayload.currentVersion else {
                return .unsupportedVersion(payload.version)
            }
            return .present(payload)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }

    /// Removes the copy. Discarding when there is nothing to discard is not an
    /// error.
    func discard() throws {
        guard FileManager.default.fileExists(atPath: copyURL.path) else { return }
        try FileManager.default.removeItem(at: copyURL)
    }

    func fileMatch(for payload: RecoveryPayload) -> RecoveryFileMatch {
        guard let path = payload.filePath else { return .notFileBacked }
        guard let recorded = payload.fileDigest else { return .differs }
        guard let current = Self.digest(ofFileAt: URL(fileURLWithPath: path)) else { return .missing }
        return current == recorded ? .matches : .differs
    }

    /// Digest of a file's bytes, or `nil` when it cannot be read.
    ///
    /// A content hash, not a size or modification time: a same-size edit, a
    /// rewritten file with its timestamps restored, and a checkout can all
    /// preserve metadata while changing the bytes.
    static func digest(ofFileAt url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
