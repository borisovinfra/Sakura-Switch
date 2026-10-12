import Foundation

/// Experimental synchronous resumable transfer with immutable per-file checkpoints.
/// Destination directory tree and journal directory must already exist.
/// No automatic repair of an unjournaled destination after an interrupted publish.
public enum SakuraResumableTransfer {
    public enum Failure: LocalizedError {
        case invalidSession, stopped, journalConflict, incompleteTransfer

        public var errorDescription: String? {
            switch self {
            case .invalidSession:
                return "Некорректный идентификатор операции."
            case .stopped:
                return "Операция остановлена: отмена или не удалось подтвердить исходный накопитель."
            case .journalConflict:
                return "Папка контрольных журналов конфликтует с источником или назначением."
            case .incompleteTransfer:
                return "Перенос не завершён: количество файлов или объём данных не совпадают."
            }
        }
    }

    public struct Progress: Sendable {
        public let verifiedFiles: Int
        public let totalFiles: Int
        public let verifiedBytes: UInt64
        public let totalBytes: UInt64
        public let checkpointName: String?
    }

    public struct Result: Sendable {
        public let checkpoint: SakuraTransferJournal.Checkpoint
        public let checkpointName: String?
        public let verifiedBytes: UInt64
    }

    /// `previousCheckpoint` must be loaded from an immutable journal checkpoint.
    /// `shouldStop` is checked only between files. On stop, a persisted checkpoint
    /// for the latest completed file remains in `journalDirectory`.
    public static func run(
        manifest: SakuraMigrationManifest.Report,
        sourceRoot: URL,
        destinationRoot: URL,
        journalDirectory: URL,
        session: String,
        previousCheckpoint: SakuraTransferJournal.Checkpoint,
        approvedSkippedPaths: Set<String> = [],
        shouldStop: () -> Bool = { false },
        onProgress: (Progress) -> Void = { _ in }
    ) throws -> Result {
        guard !session.isEmpty, session.utf8.count <= 64,
              session.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) ||
                  (48...57).contains($0) || $0 == 45 || $0 == 95 }) else {
            throw Failure.invalidSession
        }
        let source = sourceRoot.standardizedFileURL
        let destination = destinationRoot.standardizedFileURL
        let journal = journalDirectory.standardizedFileURL
        // Keep journal separate from both roots, preventing a journal from becoming
        // an unexpected source/destination manifest entry.
        for root in [source.path, destination.path] {
            guard journal.path != root, !journal.path.hasPrefix(root + "/"),
                  !root.hasPrefix(journal.path + "/") else { throw Failure.journalConflict }
        }
        // Preflight hashes all completed files from BOTH source and destination.
        // Also refuses any unjournaled file already occupying a target path.
        let validated = try SakuraResumePreflight.inspect(
            manifest: manifest, checkpoint: previousCheckpoint,
            sourceRoot: source, destinationRoot: destination,
            approvedSkippedPaths: approvedSkippedPaths)
        let ordered = manifest.entries.filter { $0.kind == .file }
            .sorted { $0.relativePath < $1.relativePath }
        guard let totalBytes = manifest.totalLogicalBytes else { throw Failure.incompleteTransfer }
        var checkpointEntries = previousCheckpoint.files
        let alreadyDone = Set(checkpointEntries.map(\.relativePath))
        var verifiedBytes = validated.verifiedCompletedBytes
        var latestName: String? = nil
        onProgress(Progress(verifiedFiles: checkpointEntries.count,
                            totalFiles: ordered.count, verifiedBytes: verifiedBytes,
                            totalBytes: totalBytes, checkpointName: nil))
        for entry in ordered where !alreadyDone.contains(entry.relativePath) {
            if shouldStop() { throw Failure.stopped }
            let relative = entry.relativePath
            let parent = (relative as NSString).deletingLastPathComponent
            let directory = parent.isEmpty ? destination : destination.appendingPathComponent(parent, isDirectory: true)
            let name = (relative as NSString).lastPathComponent
            let receipt = try SakuraVerifiedCopy.copy(
                source: source.appendingPathComponent(relative),
                toDirectory: directory, name: name)
            guard receipt.bytes == entry.logicalBytes else { throw Failure.incompleteTransfer }
            let item = SakuraTransferJournal.Entry(relativePath: relative,
                                                     bytes: receipt.bytes, sha256: receipt.sha256)
            let candidate = SakuraTransferJournal.Checkpoint(
                formatVersion: 1, files: (checkpointEntries + [item]).sorted { $0.relativePath < $1.relativePath })
            let nextCount = candidate.files.count
            let filename = String(format: "%@-%06d.json", session, nextCount)
            // Save is exclusive; a collision fails closed without altering any prior file.
            // A failure after publishing destination but before saving this checkpoint
            // intentionally requires manual reconciliation.
            try SakuraTransferJournal.save(candidate, toDirectory: journal, name: filename)
            checkpointEntries = candidate.files
            verifiedBytes += receipt.bytes
            latestName = filename
            onProgress(Progress(verifiedFiles: nextCount, totalFiles: ordered.count,
                                verifiedBytes: verifiedBytes, totalBytes: totalBytes,
                                checkpointName: filename))
        }
        guard verifiedBytes == totalBytes, checkpointEntries.count == ordered.count else {
            throw Failure.incompleteTransfer
        }
        return Result(checkpoint: SakuraTransferJournal.Checkpoint(formatVersion: 1, files: checkpointEntries),
                      checkpointName: latestName, verifiedBytes: verifiedBytes)
    }
}
