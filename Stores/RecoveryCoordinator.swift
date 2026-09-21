import Darwin
import Foundation

/// Owns the recovery copy for the in-progress document.
///
/// There is exactly one of these, constructed once at the composition root,
/// because a single `DocumentStore` is shared by every window: scheduling
/// inside the store or a view would give one writer per window for one file.
///
/// The coordinator never writes to the user's document file. It writes only
/// the recovery copy, while the document is dirty, and it discards that copy
/// the moment the document becomes clean.
@MainActor
final class RecoveryCoordinator {
    struct Configuration {
        /// How long to wait after the last edit before writing, so a burst of
        /// keystrokes coalesces into a single write.
        var debounceInterval: Duration = .seconds(2)
        /// How often the periodic tick checks, so continuous typing is still
        /// captured even when the debounce never gets a quiet moment.
        var tickInterval: Duration = .seconds(30)
        /// Payloads at or below this many UTF-8 bytes are encoded and written
        /// inline. Larger ones move off the main actor so a big paste cannot
        /// hitch the typing path.
        var synchronousSizeBound: Int = 1_048_576
    }

    private let store: RecoveryStore
    private let document: DocumentStore
    private let configuration: Configuration

    /// Test seam invoked after each successful write. Production leaves it nil.
    var onDidWrite: (@Sendable () -> Void)?

    /// Whether this process owns recovery. When false, another running copy
    /// of the app holds the lock, and every capture and restore is skipped.
    private(set) var isOwner = false

    /// Why capture and restore are disabled. Set when ownership was lost.
    private(set) var blockedReason: String?

    /// The most recent capture failure, naming the last good copy. Nil when
    /// the copy on disk is current.
    private(set) var lastError: String?

    /// When the copy on disk was last written successfully.
    private(set) var lastSuccessfulWriteAt: Date?

    /// True while a debounced capture is scheduled but has not fired.
    var hasPendingCapture: Bool { pendingTask != nil }

    private var pendingTask: Task<Void, Never>?
    private var pendingGeneration = 0
    private var tickTask: Task<Void, Never>?
    private var backgroundTask: Task<Void, Never>?
    private var lock: FileLock?
    private var attachDigest: String?
    private var attachDigestPath: String?
    private var cleanGeneration = 0
    /// Whether the current failure streak was already surfaced. A failing
    /// capture reports once; only a later success re-arms the report, so a
    /// full disk does not pop an alert on every tick.
    private var failureReported = false

    init(store: RecoveryStore, document: DocumentStore, configuration: Configuration = Configuration()) {
        self.store = store
        self.document = document
        self.configuration = configuration
        takeOwnership()
    }

    // MARK: - Document events (wired by the app in U3)

    /// The document was edited. Schedules a debounced capture, replacing any
    /// pending one, so a burst of edits produces a single write.
    func noteEdited() {
        guard isOwner else { return }
        pendingTask?.cancel()
        pendingGeneration += 1
        guard document.isDirty else {
            pendingTask = nil
            return
        }
        let generation = pendingGeneration
        pendingTask = Task { [weak self] in
            defer { self?.clearPendingTaskIfCurrent(generation) }
            guard let self else { return }
            do {
                try await Task.sleep(for: self.configuration.debounceInterval)
            } catch {
                return
            }
            self.captureIfNeeded()
        }
    }

    /// The document became clean (saved, discarded, or replaced). Call this
    /// after the flag is cleared, not before: the coordinator trusts that the
    /// document is clean and does not re-check. Cancels any pending capture
    /// and removes the copy, synchronously, so a capture scheduled before
    /// this call cannot land after it.
    func noteCleaned() {
        pendingGeneration += 1
        pendingTask?.cancel()
        pendingTask = nil
        backgroundTask?.cancel()
        backgroundTask = nil
        // Any background write already in flight must not resurrect the copy
        // this call is about to discard; see captureInBackground.
        cleanGeneration += 1
        guard isOwner else { return }
        do {
            try store.discard()
        } catch {
            lastError = "Couldn’t clear the recovery copy: \(error.localizedDescription)"
        }
    }

    /// Records the file the document was attached to, with a digest taken now.
    ///
    /// The next capture uses this digest rather than computing one, so a file
    /// that changes between attach and first capture cannot be absorbed into
    /// the check that exists to detect it.
    func noteAttachedToFile(_ url: URL?) {
        if let url {
            attachDigest = RecoveryStore.digest(ofFileAt: url)
            attachDigestPath = url.path
        } else {
            attachDigest = nil
            attachDigestPath = nil
        }
    }

    /// The digest identifying the file at `path` for save-time validation:
    /// the attach-time digest first, then a digest already on disk. Never a
    /// fresh computation — that would absorb an external change into the very
    /// check that exists to detect it.
    func recordedDigest(forPath path: String) -> String? {
        if attachDigestPath == path, let attachDigest {
            return attachDigest
        }
        if case let .present(existing) = store.read(),
           existing.filePath == path,
           let prior = existing.fileDigest
        {
            return prior
        }
        return nil
    }

    // MARK: - Launch

    /// Runs the launch sequence: takes stock of the previous session, restores
    /// a present copy into a pristine document, then writes this session's
    /// sentinel. Fully synchronous, so the app can run it in `init` before the
    /// first window renders.
    func performLaunch(sentinel: LaunchSentinel) -> LaunchOutcome {
        guard isOwner else { return .ownedElsewhere }
        let unexpectedExit = sentinel.readPriorState()
        defer { sentinel.write() }
        switch store.read() {
        case .absent:
            return .nothingToRestore
        case let .present(payload):
            let detached = document.applyRecoveryPayload(
                payload,
                checkingWith: store,
                unexpectedExit: unexpectedExit
            )
            return .restored(detached: detached, unexpectedExit: unexpectedExit)
        case let .unreadable(message):
            document.lastError = "Paper couldn’t read its recovery copy, so it opened a fresh document. (\(message))"
            return .restoreFailed(message: message)
        case let .unsupportedVersion(version):
            document.lastError = "Paper couldn’t read its recovery copy (version \(version)), so it opened a fresh document."
            return .restoreFailed(message: "unsupported version \(version)")
        }
    }

    // MARK: - Scheduling

    /// Starts the periodic tick. The app calls this once; tests call `tick()`
    /// directly instead.
    func start() {
        stopTick()
        tickTask = Task { [weak self] in
            while let self {
                do {
                    try await Task.sleep(for: self.configuration.tickInterval)
                } catch {
                    return
                }
                self.tick()
            }
        }
    }

    func stop() {
        stopTick()
    }

    /// One periodic check. Captures only while the document is dirty.
    func tick() {
        captureIfNeeded()
    }

    /// Writes the copy now, regardless of the debounce, when the document is
    /// dirty. Used by the termination flush. Returns whether a write landed.
    @discardableResult
    func captureNow() -> Bool {
        guard isOwner, document.isDirty else { return false }
        let snapshot = makePayload()
        do {
            try store.write(snapshot)
            recordSuccess(at: snapshot.lastWrittenAt)
            return true
        } catch {
            // Termination is the only caller; an alert then would be noise on
            // top of a dying app, so the failure stays on the coordinator.
            lastError = Self.failureMessage(underlying: error, lastGood: lastSuccessfulWriteAt)
            return false
        }
    }

    // MARK: - Test hooks

    /// Waits for a pending debounced capture to finish or be cancelled.
    func waitForPendingCapture() async {
        await pendingTask?.value
    }

    /// Waits for an in-flight background capture to finish.
    func waitForBackgroundWork() async {
        await backgroundTask?.value
    }

    // MARK: - Private

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func clearPendingTaskIfCurrent(_ generation: Int) {
        if pendingGeneration == generation {
            pendingTask = nil
        }
    }

    private func captureIfNeeded() {
        guard isOwner, document.isDirty else { return }
        let snapshot = makePayload()
        if snapshot.text.utf8.count > configuration.synchronousSizeBound {
            captureInBackground(snapshot)
        } else {
            do {
                try store.write(snapshot)
                recordSuccess(at: snapshot.lastWrittenAt)
                onDidWrite?()
            } catch {
                recordFailure(Self.failureMessage(underlying: error, lastGood: lastSuccessfulWriteAt))
            }
        }
    }

    private func captureInBackground(_ snapshot: RecoveryPayload) {
        backgroundTask?.cancel()
        let generation = cleanGeneration
        backgroundTask = Task.detached { [store, snapshot] in
            if Task.isCancelled { return }
            do {
                try store.write(snapshot)
            } catch {
                await MainActor.run { [weak self] in
                    self?.recordFailure(Self.failureMessage(underlying: error, lastGood: self?.lastSuccessfulWriteAt))
                }
                return
            }
            // A clean that landed while the write was in flight wins: the copy
            // it discarded must not be resurrected.
            await MainActor.run { [weak self] in
                guard let self else { return }
                if generation == self.cleanGeneration {
                    self.recordSuccess(at: snapshot.lastWrittenAt)
                    self.onDidWrite?()
                } else {
                    try? self.store.discard()
                }
            }
        }
    }

    private func makePayload() -> RecoveryPayload {
        let filePath = document.fileURL?.path
        let digest: String? = {
            guard let path = filePath else { return nil }
            // Prefer the explicitly recorded attach-time digest, then a digest
            // already on disk. A capture never blindly refreshes the digest:
            // that would absorb an external change into the check.
            if attachDigestPath == path, let attachDigest {
                return attachDigest
            }
            if case let .present(existing) = store.read(),
               existing.filePath == path,
               let prior = existing.fileDigest
            {
                return prior
            }
            return RecoveryStore.digest(ofFileAt: URL(fileURLWithPath: path))
        }()
        return RecoveryPayload(
            text: document.text,
            title: document.documentTitle,
            filePath: filePath,
            fileDigest: digest,
            lastWrittenAt: Date()
        )
    }

    private static func failureMessage(underlying error: Error, lastGood: Date?) -> String {
        if let lastGood {
            let formatter = RelativeDateTimeFormatter()
            return "Couldn’t save the recovery copy (last good copy \(formatter.localizedString(for: lastGood, relativeTo: Date()))). \(error.localizedDescription)"
        }
        return "Couldn’t save the recovery copy. \(error.localizedDescription)"
    }

    private func recordSuccess(at date: Date) {
        lastSuccessfulWriteAt = date
        lastError = nil
        failureReported = false
    }

    private func recordFailure(_ message: String) {
        lastError = message
        if !failureReported {
            failureReported = true
            document.lastError = message
        }
    }

    // MARK: - Ownership

    /// Takes exclusive ownership of the recovery directory for this process.
    /// A held lock survives nothing: the OS releases it when the process
    /// dies, so a crash cannot leave recovery permanently owned.
    private func takeOwnership() {
        do {
            try FileManager.default.createDirectory(
                at: store.directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            blockedReason = "Couldn’t prepare the recovery directory: \(error.localizedDescription)"
            return
        }
        let lockURL = store.directory.appendingPathComponent("owner.lock")
        guard let fileLock = FileLock(path: lockURL.path) else {
            blockedReason = "Recovery is already owned by another running copy of Paper; capture and restore are disabled here."
            return
        }
        lock = fileLock
        isOwner = true
    }
}

/// What the launch sequence found.
enum LaunchOutcome: Equatable {
    case restored(detached: Bool, unexpectedExit: Bool)
    case nothingToRestore
    case restoreFailed(message: String)
    case ownedElsewhere
}

/// An exclusive, non-blocking lock on a file.
///
/// Held for the owner's lifetime and released by the OS on process death, so
/// a crash cannot strand ownership. Two separate opens of the same path
/// contend even inside one process, which is what makes ownership testable.
private final class FileLock {
    let fileDescriptor: Int32

    init?(path: String) {
        let fileDescriptor = path.withCString { open($0, O_CREAT | O_RDWR, 0o600) }
        guard fileDescriptor >= 0 else { return nil }
        guard flock(fileDescriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(fileDescriptor)
            return nil
        }
        self.fileDescriptor = fileDescriptor
    }

    deinit {
        close(fileDescriptor)
    }
}
