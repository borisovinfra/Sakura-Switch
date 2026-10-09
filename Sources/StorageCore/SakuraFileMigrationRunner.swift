import Foundation

/// File migration orchestration.
/// Disk authorization must be performed by the caller.
/// This component never formats or repartitions disks.
public enum SakuraFileMigrationRunner {

    public enum Failure: Error {
        case incompleteManifest
        case excludedPaths
        case insufficientSpace
    }

    public struct Preparation: Sendable {
        public let manifest: SakuraMigrationManifest.Report
        public let directories: SakuraDestinationDirectoryPlan.Plan
        public let requiredBytes: UInt64
        public let approvedSkippedPaths: Set<String>
    }

    /// Read-only preparation. No destination files are created.
    public static func inspect(
        sourceRoot: URL,
        approvedSkippedPaths: Set<String> = []
    ) throws -> Preparation {
        let policy: SakuraMigrationInventory.Policy =
            approvedSkippedPaths.isEmpty ? .strict : .excludeKnownMacOSMetadata

        let manifest = SakuraMigrationManifest.inspect(
            root: sourceRoot, policy: policy
        )

        guard manifest.complete,
              let bytes = manifest.totalLogicalBytes else {
            throw Failure.incompleteManifest
        }

        guard Set(manifest.skippedPaths) == approvedSkippedPaths else {
            throw Failure.excludedPaths
        }

        for path in approvedSkippedPaths {
            let name = (path as NSString).lastPathComponent
            let topLevel = !path.contains("/")
            let knownFile = name.hasPrefix("._") || name == ".DS_Store"
            let knownDirectory = topLevel &&
                [".Spotlight-V100", ".Trashes", ".fseventsd"].contains(name)

            guard knownFile || knownDirectory else {
                throw Failure.excludedPaths
            }
        }

        let directories = manifest.entries
            .filter { $0.kind == .directory }
            .map(\.relativePath)

        let files = manifest.entries
            .filter { $0.kind == .file }
            .map(\.relativePath)

        let plan = try SakuraDestinationDirectoryPlan.make(
            directories: directories,
            files: files
        )

        return Preparation(
            manifest: manifest,
            directories: plan,
            requiredBytes: bytes,
            approvedSkippedPaths: approvedSkippedPaths
        )
    }

    /// Call only after independently authorizing both volumes.
    /// Journal directory must already exist outside both volumes.
    public static func run(
        preparation: Preparation,
        sourceRoot: URL,
        destinationRoot: URL,
        journalDirectory: URL,
        session: String,
        checkpoint: SakuraTransferJournal.Checkpoint,
        savedSession: SakuraMigrationSession.Record,
        sourceVolumeUUID: String,
        targetVolumeUUID: String,
        revalidate: () throws -> Void,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void
    ) throws -> SakuraResumableTransfer.Result {

        func verifySession() throws {
            try revalidate()

            let current = try SakuraMigrationSession.make(
                sessionID: session,
                sourceVolumeUUID: sourceVolumeUUID,
                targetVolumeUUID: targetVolumeUUID,
                manifest: preparation.manifest,
                approvedSkippedPaths: preparation.approvedSkippedPaths
            )

            let passportURL = journalDirectory.appendingPathComponent(
                session + ".session.json"
            )

            let persisted = try SakuraMigrationSession.load(
                from: passportURL
            )

            try SakuraMigrationSession.validate(
                saved: persisted,
                current: current
            )

            try SakuraMigrationSession.validate(
                saved: persisted,
                current: savedSession
            )
        }

        try verifySession()

        var previousBytes: UInt64 = 0
        for file in checkpoint.files {
            let (sum, overflow) = previousBytes.addingReportingOverflow(file.bytes)
            guard !overflow else { throw Failure.incompleteManifest }
            previousBytes = sum
        }

        guard previousBytes <= preparation.requiredBytes else {
            throw Failure.incompleteManifest
        }

        let remainingBytes = preparation.requiredBytes - previousBytes
        let (requiredSpace, overflow) =
            remainingBytes.addingReportingOverflow(1_073_741_824)
        guard !overflow else { throw Failure.insufficientSpace }

        let values = try destinationRoot.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )

        guard let available = values.volumeAvailableCapacity,
              available >= 0,
              UInt64(available) >= requiredSpace else {
            throw Failure.insufficientSpace
        }

        try SakuraDestinationDirectoryPreparer.prepare(
            plan: preparation.directories,
            root: destinationRoot
        )

        try verifySession()

        var validationFailure: Error?

        let result: SakuraResumableTransfer.Result
        do {
            result = try SakuraResumableTransfer.run(
                manifest: preparation.manifest,
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot,
                journalDirectory: journalDirectory,
                session: session,
                previousCheckpoint: checkpoint,
                approvedSkippedPaths: preparation.approvedSkippedPaths,
                shouldStop: {
                    if shouldStop() { return true }
                    do {
                        try verifySession()
                        return false
                    } catch {
                        validationFailure = error
                        return true
                    }
                },
                onProgress: onProgress
            )
        } catch {
            if let validationFailure {
                throw validationFailure
            }
            throw error
        }

        try verifySession()

        let count = try SakuraTransferJournal.verify(
            result.checkpoint,
            at: destinationRoot
        )

        guard count == preparation.manifest.fileCount else {
            throw SakuraResumableTransfer.Failure.incompleteTransfer
        }

        return result
    }
}
