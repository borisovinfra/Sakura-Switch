import Foundation
import StorageCore

enum SakuraBackupEngine {
    private enum ResumeFailure: LocalizedError {
        case sourceMetadata(String)
        case sourceChanged

        var errorDescription: String? {
            switch self {
            case .sourceMetadata(let details):
                return "Не удалось подтвердить исходную карту после трёх попыток: " + details
            case .sourceChanged:
                return "Паспорт исходного накопителя изменился. Резервирование остановлено."
            }
        }
    }

    private final class ResumeStopReason: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: ResumeFailure?

        func record(_ reason: ResumeFailure) {
            lock.lock()
            defer { lock.unlock() }
            if stored == nil { stored = reason }
        }

        func get() -> ResumeFailure? {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    struct Result {
        let backupFolder: URL
        let fileCount: Int
        let verifiedBytes: UInt64
    }

    static func prepare(
        diskID: String,
        destination: URL
    ) throws -> SakuraBackupPreflightResult {
        try SakuraBackupPreflight.inspect(
            diskID: diskID,
            destination: destination
        )
    }

    static func createBackupFolder(
        diskID: String,
        destination: URL
    ) throws -> URL {
        _ = try SakuraBackupPreflight.inspect(
            diskID: diskID,
            destination: destination
        )
        return try SakuraBackupDirectory.create(in: destination)
    }

    static func prepareBackupStructure(
        diskID: String,
        destination: URL
    ) throws -> URL {
        let root = try createBackupFolder(
            diskID: diskID,
            destination: destination
        )
        let data = root.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(
            at: data,
            withIntermediateDirectories: false
        )
        return root
    }

    static func createJournal() throws -> (URL, String) {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/SakuraSwitch/Backups",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: base, withIntermediateDirectories: true
        )
        let session = "SakuraBackup-" + UUID().uuidString
        let journal = base.appendingPathComponent(session, isDirectory: true)
        try FileManager.default.createDirectory(
            at: journal, withIntermediateDirectories: false
        )
        return (journal, session)
    }

    static func copyFiles(
        source: URL,
        destination: URL,
        journal: URL,
        session: String,
        preparation: SakuraFileMigrationRunner.Preparation,
        approvedSkippedPaths: Set<String>,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void,
        previousCheckpoint: SakuraTransferJournal.Checkpoint = .init(
            formatVersion: 1, files: []
        )
    ) throws -> SakuraResumableTransfer.Result {
        try SakuraDestinationDirectoryPreparer.prepare(
            plan: preparation.directories, root: destination
        )
        return try SakuraResumableTransfer.run(
            manifest: preparation.manifest,
            sourceRoot: source,
            destinationRoot: destination,
            journalDirectory: journal,
            session: session,
            previousCheckpoint: previousCheckpoint,
            approvedSkippedPaths: approvedSkippedPaths,
            shouldStop: shouldStop,
            onProgress: onProgress
        )
    }

    static func verifyBackup(
        checkpoint: SakuraTransferJournal.Checkpoint,
        dataRoot: URL,
        onProgress: (Int, Int) -> Void
    ) throws -> Int {
        onProgress(0, checkpoint.files.count)
        return try SakuraTransferJournal.verify(
            checkpoint,
            at: dataRoot,
            onProgress: onProgress
        )
    }

    static func finalizeBackup(
        checkpoint: SakuraTransferJournal.Checkpoint,
        backupRoot: URL,
        expectedFiles: Int,
        onProgress: (Int, Int) -> Void
    ) throws {
        guard checkpoint.files.count == expectedFiles else {
            throw SakuraResumableTransfer.Failure.incompleteTransfer
        }
        let dataRoot = backupRoot.appendingPathComponent(
            "data", isDirectory: true
        )
        let verified = try verifyBackup(
            checkpoint: checkpoint,
            dataRoot: dataRoot,
            onProgress: onProgress
        )
        guard verified == expectedFiles else {
            throw SakuraResumableTransfer.Failure.incompleteTransfer
        }
        try SakuraTransferJournal.save(
            checkpoint,
            toDirectory: backupRoot,
            name: "checksums.json"
        )
    }

    static func run(
        diskID: String,
        destination: URL,
        approvedSkippedPaths: Set<String>,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void,
        onVerification: (Int, Int) -> Void
    ) throws -> Result {
        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }

        let passport = try sourcePassport(diskID: diskID)
        let source = try SakuraPhysicalMigrationEngine.sourceRoot(for: diskID)
        try SakuraBackupSafety.validate(
            sourceRoot: source,
            destinationFolder: destination
        )
        let preparation = try SakuraFileMigrationRunner.inspect(
            sourceRoot: source,
            approvedSkippedPaths: approvedSkippedPaths
        )

        return try executeBackup(
            diskID: diskID,
            source: source,
            destination: destination,
            preparation: preparation,
            approvedSkippedPaths: approvedSkippedPaths,
            passport: passport,
            shouldStop: shouldStop,
            onProgress: onProgress,
            onVerification: onVerification
        )
    }

    private static func executeBackup(
        diskID: String,
        source: URL,
        destination: URL,
        preparation: SakuraFileMigrationRunner.Preparation,
        approvedSkippedPaths: Set<String>,
        passport: SakuraDiskIdentityGuard.Snapshot,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void,
        onVerification: (Int, Int) -> Void
    ) throws -> Result {
        let check = try SakuraBackupPreflight.inspect(
            diskID: diskID, destination: destination
        )
        guard check.requiredBytes == preparation.requiredBytes,
              Set(check.skippedPaths) == approvedSkippedPaths else {
            throw SakuraResumableTransfer.Failure.incompleteTransfer
        }

        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }

        let initialPassport: SakuraDiskIdentityGuard.Snapshot
        do {
            initialPassport = try stableSourcePassport(diskID: diskID)
        } catch {
            throw ResumeFailure.sourceMetadata("перед созданием копии: " + String(describing: error))
        }
        guard SakuraDiskIdentityGuard.assess(
            previous: passport, current: initialPassport
        ) != .changed else {
            throw ResumeFailure.sourceChanged
        }

        let root = try prepareBackupStructure(
            diskID: diskID, destination: destination
        )
        let data = root.appendingPathComponent("data", isDirectory: true)
        let (journal, session) = try createJournal()

        try SakuraBackupSafety.validate(
            sourceRoot: source,
            destinationFolder: destination
        )

        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }

        let stopReason = ResumeStopReason()
        // Never throttle user cancellation. Refresh disk identity at most once
        // every 10 seconds during file copying; fail closed on any bad snapshot.
        var lastIdentityCheck = -Double.infinity
        let transfer: SakuraResumableTransfer.Result
        do {
            transfer = try copyFiles(
                source: source,
                destination: data,
                journal: journal,
                session: session,
                preparation: preparation,
                approvedSkippedPaths: approvedSkippedPaths,
                shouldStop: {
                    if shouldStop() { return true }
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - lastIdentityCheck < 10 { return false }
                    // If validation fails, do NOT advance the polling clock.
                    let currentRoot: URL
                    do {
                        currentRoot = try SakuraPhysicalMigrationEngine.sourceRoot(for: diskID)
                    } catch {
                        stopReason.record(.sourceMetadata(
                            "при определении точки монтирования: " + String(describing: error)))
                        return true
                    }
                    guard currentRoot == source else {
                        stopReason.record(.sourceChanged)
                        return true
                    }
                    do {
                        let currentPassport = try stableSourcePassport(diskID: diskID)
                        if SakuraDiskIdentityGuard.assess(
                            previous: passport, current: currentPassport
                        ) == .changed {
                            stopReason.record(.sourceChanged)
                            return true
                        }
                        lastIdentityCheck = now
                        return false
                    } catch {
                        stopReason.record(.sourceMetadata(
                            "при проверке паспорта: " + String(describing: error)))
                        return true
                    }
                },
                onProgress: onProgress
            )
        } catch SakuraResumableTransfer.Failure.stopped {
            if let reason = stopReason.get() { throw reason }
            throw SakuraResumableTransfer.Failure.stopped
        }

        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }
        let finalPassport: SakuraDiskIdentityGuard.Snapshot
        do {
            finalPassport = try stableSourcePassport(diskID: diskID)
        } catch {
            throw ResumeFailure.sourceMetadata("после копирования: " + String(describing: error))
        }
        guard SakuraDiskIdentityGuard.assess(
            previous: passport, current: finalPassport
        ) != .changed else {
            throw ResumeFailure.sourceChanged
        }

        try finalizeBackup(
            checkpoint: transfer.checkpoint,
            backupRoot: root,
            expectedFiles: preparation.manifest.fileCount,
            onProgress: onVerification
        )

        return Result(
            backupFolder: root,
            fileCount: transfer.checkpoint.files.count,
            verifiedBytes: transfer.verifiedBytes
        )
    }

    static func resumeBackup(
        diskID: String,
        backupRoot: URL,
        journalDirectory: URL,
        session: String,
        checkpointURL: URL,
        approvedSkippedPaths: Set<String>,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void,
        onVerification: (Int, Int) -> Void
    ) throws -> Result {
        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }

        // Do not allow a checkpoint from another session or an already finished backup.
        guard checkpointURL.deletingLastPathComponent().standardizedFileURL == journalDirectory.standardizedFileURL,
              checkpointURL.lastPathComponent.hasPrefix(session + "-"),
              checkpointURL.pathExtension == "json",
              journalDirectory.lastPathComponent == session,
              !FileManager.default.fileExists(
                  atPath: backupRoot.appendingPathComponent("checksums.json").path
              ) else {
            throw SakuraTransferJournal.Failure.invalidPath
        }

        let passport = try stableSourcePassport(diskID: diskID)
        let source = try SakuraPhysicalMigrationEngine.sourceRoot(for: diskID)
        let data = backupRoot.appendingPathComponent("data", isDirectory: true)

        try SakuraBackupSafety.validate(
            sourceRoot: source,
            destinationFolder: backupRoot
        )

        let checkpoint = try SakuraTransferJournal.load(from: checkpointURL)
        let preparation = try SakuraFileMigrationRunner.inspect(
            sourceRoot: source,
            approvedSkippedPaths: approvedSkippedPaths
        )

        let stopReason = ResumeStopReason()
        // Same policy as a fresh backup, including an immediate first check.
        var lastIdentityCheck = -Double.infinity
        let transfer: SakuraResumableTransfer.Result
        do {
            transfer = try copyFiles(
            source: source,
            destination: data,
            journal: journalDirectory,
            session: session,
            preparation: preparation,
            approvedSkippedPaths: approvedSkippedPaths,
            shouldStop: {
                if shouldStop() { return true }
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastIdentityCheck < 10 { return false }
                do {
                    let current = try stableSourcePassport(diskID: diskID)
                    if SakuraDiskIdentityGuard.assess(
                        previous: passport, current: current
                    ) == .changed {
                        stopReason.record(.sourceChanged)
                        return true
                    }
                    lastIdentityCheck = now
                    return false
                } catch {
                    stopReason.record(.sourceMetadata(String(describing: error)))
                    return true
                }
            },
            onProgress: onProgress,
            previousCheckpoint: checkpoint
            )
        } catch SakuraResumableTransfer.Failure.stopped {
            if let reason = stopReason.get() { throw reason }
            throw SakuraResumableTransfer.Failure.stopped
        }

        guard !shouldStop() else {
            throw SakuraResumableTransfer.Failure.stopped
        }
        let finalPassport: SakuraDiskIdentityGuard.Snapshot
        do {
            finalPassport = try stableSourcePassport(diskID: diskID)
        } catch {
            throw ResumeFailure.sourceMetadata(String(describing: error))
        }
        guard SakuraDiskIdentityGuard.assess(
            previous: passport, current: finalPassport
        ) != .changed else {
            throw ResumeFailure.sourceChanged
        }

        try finalizeBackup(
            checkpoint: transfer.checkpoint,
            backupRoot: backupRoot,
            expectedFiles: preparation.manifest.fileCount,
            onProgress: onVerification
        )

        return Result(
            backupFolder: backupRoot,
            fileCount: transfer.checkpoint.files.count,
            verifiedBytes: transfer.verifiedBytes
        )
    }

    private static func stableSourcePassport(
        diskID: String
    ) throws -> SakuraDiskIdentityGuard.Snapshot {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try sourcePassport(diskID: diskID)
            } catch {
                lastError = error
                if attempt < 2 {
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }
        throw lastError ?? SakuraDiskIdentityGuard.Failure.invalidDisk
    }

    private static func sourcePassport(
        diskID: String
    ) throws -> SakuraDiskIdentityGuard.Snapshot {
        let source = try SakuraPhysicalMigrationEngine.sourceRoot(for: diskID)

        func info(_ identifier: String) throws -> [String: Any] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
            process.arguments = ["info", "-plist", identifier]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let result = try PropertyListSerialization.propertyList(
                    from: data, format: nil
                  ) as? [String: Any] else {
                throw SakuraDiskIdentityGuard.Failure.invalidDisk
            }
            return result
        }

        let disk = try info(diskID)
        let parts = try StoragePartitionInspector.partitions(for: diskID)
        guard let selected = parts.first(where: {
            let details = try? info($0.id)
            return details?["MountPoint"] as? String == source.path
        }) else {
            throw SakuraDiskIdentityGuard.Failure.invalidPartition
        }

        return try SakuraDiskIdentityGuard.capture(
            disk: disk,
            partition: info(selected.id)
        )
    }
}
