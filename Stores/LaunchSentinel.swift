import Foundation

/// Tracks whether the previous session ended gracefully.
///
/// Written at launch and removed on graceful termination. Its presence at the
/// next launch means the last session crashed or was force-quit. It decides
/// only how a restore is described, never whether one happens and never what
/// happens to the copy: the recovery copy is written continuously and exists
/// independently of this marker.
struct LaunchSentinel {
    let url: URL

    init(directory: URL) {
        self.url = directory.appendingPathComponent("sentinel")
    }

    /// Whether a previous session left its sentinel behind.
    /// Read before `write()` in the same launch.
    func readPriorState() -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func write() {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        FileManager.default.createFile(
            atPath: url.path,
            contents: Data(Date().timeIntervalSince1970.description.utf8)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}
