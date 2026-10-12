import Foundation
import StorageCore

enum SakuraRestoreEngine {
    enum Failure: LocalizedError {
        case invalidBackup
        case destinationNotEmpty
        case nestedDestination

        var errorDescription: String? {
            switch self {
            case .invalidBackup:
                return "Резервная копия не прошла проверку."
            case .destinationNotEmpty:
                return "На целевом накопителе обнаружены файлы или посторонние каталоги."
            case .nestedDestination:
                return "Нельзя восстанавливать файлы внутрь резервной копии."
            }
        }
    }

    /// Allows only ordinary system-created macOS metadata directories at the root.
    /// All other existing destination objects block restoration.
    static func destinationIsEffectivelyEmpty(_ folder: URL) throws -> Bool {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let root = try folder.resourceValues(forKeys: keys)
        guard root.isDirectory == true, root.isSymbolicLink != true else { return false }

        let allowed = Set([".fseventsd", ".Spotlight-V100"])
        let children = try FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: []
        )
        for child in children {
            guard allowed.contains(child.lastPathComponent) else { return false }
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                return false
            }
        }
        return true
    }

    static func preflight(
        backup: URL,
        destination: URL
    ) throws -> SakuraTransferJournal.Checkpoint {
        let source = backup.standardizedFileURL
        let target = destination.standardizedFileURL

        guard source != target,
              !target.path.hasPrefix(source.path + "/"),
              !source.path.hasPrefix(target.path + "/") else {
            throw Failure.nestedDestination
        }

        guard try destinationIsEffectivelyEmpty(target) else {
            throw Failure.destinationNotEmpty
        }

        let checkpoint = try SakuraTransferJournal.load(
            from: source.appendingPathComponent("checksums.json")
        )
        let data = source.appendingPathComponent("data", isDirectory: true)

        let preparation = try SakuraFileMigrationRunner.inspect(sourceRoot: data)
        let expected = Dictionary(
            uniqueKeysWithValues: checkpoint.files.map { ($0.relativePath, $0.bytes) }
        )
        let actual = Dictionary(
            uniqueKeysWithValues: preparation.manifest.entries
                .filter { $0.kind == .file }
                .map { ($0.relativePath, $0.logicalBytes) }
        )
        guard expected == actual else {
            throw Failure.invalidBackup
        }

        guard try SakuraTransferJournal.verify(checkpoint, at: data)
                == checkpoint.files.count else {
            throw Failure.invalidBackup
        }

        return checkpoint
    }

    static func restore(
        backup: URL,
        destination: URL,
        journalDirectory: URL,
        shouldStop: @escaping () -> Bool,
        onProgress: @escaping (SakuraResumableTransfer.Progress) -> Void,
        onVerification: @escaping (Int, Int) -> Void
    ) throws -> Int {
        let expected = try preflight(backup: backup, destination: destination)
        let source = backup.appendingPathComponent("data", isDirectory: true)
        let preparation = try SakuraFileMigrationRunner.inspect(sourceRoot: source)

        try SakuraDestinationDirectoryPreparer.prepare(
            plan: preparation.directories,
            root: destination
        )

        let result = try SakuraResumableTransfer.run(
            manifest: preparation.manifest,
            sourceRoot: source,
            destinationRoot: destination,
            journalDirectory: journalDirectory,
            session: "SakuraRestore-" + UUID().uuidString,
            previousCheckpoint: SakuraTransferJournal.Checkpoint(
                formatVersion: 1, files: []
            ),
            shouldStop: shouldStop,
            onProgress: onProgress
        )

        guard result.checkpoint.files == expected.files else {
            throw Failure.invalidBackup
        }

        let verified = try SakuraTransferJournal.verify(
            result.checkpoint,
            at: destination,
            onProgress: onVerification
        )
        guard verified == expected.files.count else {
            throw Failure.invalidBackup
        }
        return verified
    }

}
