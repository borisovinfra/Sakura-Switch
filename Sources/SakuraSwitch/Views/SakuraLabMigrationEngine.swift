import Foundation
import StorageCore
import Darwin

enum SakuraLabMigrationEngine {
    private static let session = "SakuraLabFile001"

    private static let source = URL(
        fileURLWithPath: "/Volumes/NINTENDO", isDirectory: true
    )
    private static let destination = URL(
        fileURLWithPath: "/Volumes/SAKURASD", isDirectory: true
    )

    private static var lab: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Downloads/SakuraSwitch-StorageCenter/.storage-tests/SakuraMigrationLab",
                isDirectory: true
            )
    }

    private static var imagePath: String {
        lab.appendingPathComponent("SakuraVirtualSD.sparseimage").path
    }

    private static var journal: URL {
        lab.appendingPathComponent("MigrationJournal", isDirectory: true)
    }

    private static func diskInfo(_ identifier: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", identifier]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        guard process.terminationStatus == 0,
              let result = try PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any] else {
            throw LabError.invalidDisk
        }
        return result
    }

    private static func verifyVolumes() throws -> (String, String) {
        let src = try diskInfo(source.path)
        guard src["MountPoint"] as? String == source.path,
              src["FilesystemName"] as? String == "MS-DOS FAT32",
              src["VolumeName"] as? String == "NINTENDO",
              let parent = src["ParentWholeDisk"] as? String,
              let sourceUUID = src["VolumeUUID"] as? String else {
            throw LabError.invalidSource
        }

        let wholeDisk = try diskInfo(parent)
        guard wholeDisk["DeviceIdentifier"] as? String == parent,
              wholeDisk["WholeDisk"] as? Bool == true,
              wholeDisk["VirtualOrPhysical"] as? String == "Physical" else {
            throw LabError.invalidSource
        }

        try SakuraVirtualDiskGuard.verify(
            imagePath: imagePath,
            volumePath: destination.path
        )

        let dst = try diskInfo(destination.path)
        guard let targetUUID = dst["VolumeUUID"] as? String,
              sourceUUID != targetUUID else {
            throw LabError.invalidDisk
        }

        return (sourceUUID, targetUUID)
    }

    // Refuse symlink components in the journal directory.
    private static func verifyDirectory(_ url: URL) throws {
        var path = "/"
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            path = (path as NSString).appendingPathComponent(component)
            var metadata = stat()
            guard lstat(path, &metadata) == 0,
                  (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw LabError.unsafeJournal
            }
        }
    }

    private static func prepareJournal() throws {
        try verifyDirectory(lab)
        let fm = FileManager.default
        if !fm.fileExists(atPath: journal.path) {
            try fm.createDirectory(at: journal, withIntermediateDirectories: false)
        }
        try verifyDirectory(journal)
    }

    private static func previousCheckpoint() throws
        -> SakuraTransferJournal.Checkpoint {

        let names = try FileManager.default.contentsOfDirectory(
            atPath: journal.path
        )

        let prefix = session + "-"
        let checkpoints = names.compactMap { name -> (Int, String)? in
            guard name.hasPrefix(prefix), name.hasSuffix(".json") else {
                return nil
            }
            let digits = name.dropFirst(prefix.count).dropLast(5)
            guard digits.count == 6,
                  digits.allSatisfy(\.isNumber),
                  let number = Int(digits), number > 0 else {
                return nil
            }
            return (number, name)
        }.sorted { $0.0 < $1.0 }

        for (index, item) in checkpoints.enumerated() {
            guard item.0 == index + 1 else {
                throw LabError.invalidCheckpoint
            }
        }

        guard let latest = checkpoints.last else {
            return SakuraTransferJournal.Checkpoint(
                formatVersion: 1, files: []
            )
        }

        let checkpoint = try SakuraTransferJournal.load(
            from: journal.appendingPathComponent(latest.1)
        )
        guard checkpoint.files.count == latest.0 else {
            throw LabError.invalidCheckpoint
        }
        return checkpoint
    }

    static func run(
        approvedSkippedPaths: Set<String>,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void
    ) throws -> SakuraResumableTransfer.Result {

        guard !shouldStop() else { throw LabError.cancelled }

        let (sourceUUID, targetUUID) = try verifyVolumes()
        try prepareJournal()

        let preparation = try SakuraFileMigrationRunner.inspect(
            sourceRoot: source,
            approvedSkippedPaths: approvedSkippedPaths
        )

        let record = try SakuraMigrationSession.make(
            sessionID: session,
            sourceVolumeUUID: sourceUUID,
            targetVolumeUUID: targetUUID,
            manifest: preparation.manifest,
            approvedSkippedPaths: approvedSkippedPaths
        )

        // Complete preflight before creating the session passport.
        // Read the existing checkpoint without modifying either volume.
        let checkpoint = try previousCheckpoint()

        let completedBytes = checkpoint.files.reduce(UInt64(0)) {
            partial, entry in
            let (sum, overflow) = partial.addingReportingOverflow(entry.bytes)
            return overflow ? UInt64.max : sum
        }

        guard completedBytes <= preparation.requiredBytes else {
            throw LabError.invalidCheckpoint
        }

        let (requiredSpace, spaceOverflow) =
            (preparation.requiredBytes - completedBytes)
                .addingReportingOverflow(1_073_741_824)

        guard !spaceOverflow else {
            throw LabError.insufficientSpace
        }

        let capacity = try destination.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )

        guard let available = capacity.volumeAvailableCapacity,
              available >= 0,
              UInt64(available) >= requiredSpace else {
            throw LabError.insufficientSpace
        }

        // The destination directories must exist before resume preflight.
        // This operation is restricted to the independently verified
        // virtual SAKURASD image.
        let volumesBeforePreparation = try verifyVolumes()
        guard volumesBeforePreparation.0 == sourceUUID,
              volumesBeforePreparation.1 == targetUUID else {
            throw LabError.invalidDisk
        }

        try SakuraDestinationDirectoryPreparer.prepare(
            plan: preparation.directories,
            root: destination
        )

        // Check resumed files and refuse unjournaled destinations
        // before publishing any new session passport.
        _ = try SakuraResumePreflight.inspect(
            manifest: preparation.manifest,
            checkpoint: checkpoint,
            sourceRoot: source,
            destinationRoot: destination,
            approvedSkippedPaths: approvedSkippedPaths
        )

        guard !shouldStop() else {
            throw LabError.cancelled
        }

        let confirmed = try verifyVolumes()
        guard confirmed.0 == sourceUUID,
              confirmed.1 == targetUUID else {
            throw LabError.invalidDisk
        }

        try verifyDirectory(journal)

        let passportURL = journal.appendingPathComponent(
            session + ".session.json"
        )

        var passportInfo = stat()
        let passportExists = lstat(passportURL.path, &passportInfo) == 0

        if passportExists {
            guard (passportInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG)
            else { throw LabError.unsafeJournal }

            let persisted = try SakuraMigrationSession.load(
                from: passportURL
            )
            try SakuraMigrationSession.validate(
                saved: persisted, current: record
            )
        } else {
            let names = try FileManager.default.contentsOfDirectory(
                atPath: journal.path
            )
            guard !names.contains(where: {
                $0.hasPrefix(session + "-")
            }) else {
                throw LabError.invalidCheckpoint
            }
            try SakuraMigrationSession.save(record, to: passportURL)
        }

        guard !shouldStop() else { throw LabError.cancelled }

        return try SakuraFileMigrationRunner.run(
            preparation: preparation,
            sourceRoot: source,
            destinationRoot: destination,
            journalDirectory: journal,
            session: session,
            checkpoint: checkpoint,
            savedSession: record,
            sourceVolumeUUID: sourceUUID,
            targetVolumeUUID: targetUUID,
            revalidate: {
                do {
                    try verifyDirectory(journal)
                } catch {
                    throw NSError(
                        domain: "SakuraMigration.JournalRevalidation",
                        code: 1,
                        userInfo: [NSUnderlyingErrorKey: error]
                    )
                }

                let current: (String, String)
                do {
                    current = try verifyVolumes()
                } catch {
                    throw NSError(
                        domain: "SakuraMigration.VolumeRevalidation",
                        code: 2,
                        userInfo: [NSUnderlyingErrorKey: error]
                    )
                }

                guard current.0 == sourceUUID,
                      current.1 == targetUUID else {
                    throw LabError.invalidDisk
                }
            },
            shouldStop: shouldStop,
            onProgress: onProgress
        )
    }

    enum LabError: LocalizedError {
        case invalidDisk
        case invalidSource
        case unsafeJournal
        case invalidCheckpoint
        case insufficientSpace
        case cancelled

        var errorDescription: String? {
            switch self {
            case .invalidDisk:
                return "Идентификаторы накопителей не подтверждены."
            case .invalidSource:
                return "Источник не подтверждён как физическая FAT32 NINTENDO."
            case .unsafeJournal:
                return "Каталог журнала отсутствует или содержит небезопасный путь."
            case .invalidCheckpoint:
                return "Контрольные точки сеанса повреждены или неполны."
            case .insufficientSpace:
                return "Недостаточно свободного места на виртуальной SAKURASD."
            case .cancelled:
                return "Остановлено до начала копирования."
            }
        }
    }
}
