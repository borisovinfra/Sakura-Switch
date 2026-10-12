import Foundation
import StorageCore
import Darwin
import CryptoKit

enum SakuraPhysicalMigrationEngine {
    private static var journalBase: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SakuraSwitch/PhysicalMigrations", isDirectory: true)
    }
    private static func sessionID(_ sourceUUID: String, _ targetUUID: String) -> String {
        let digest = SHA256.hash(data: Data((sourceUUID + "|" + targetUUID).utf8))
        return "SakuraPhysical" + digest.prefix(10).map { String(format: "%02x", $0) }.joined()
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

    struct Volumes {
        let source: URL
        let target: URL
        let sourceUUID: String
        let targetUUID: String
    }

    // Re-resolve both physical disks every time; never trust the selected UI names.
    private static func verifyVolumes(sourceDiskID: String, targetDiskID: String) throws -> Volumes {
        guard sourceDiskID != targetDiskID,
              sourceDiskID.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              targetDiskID.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            throw LabError.invalidDisk
        }
        func mountedFAT32(_ id: String) throws -> (URL, String) {
            let disk = try diskInfo(id)
            guard disk["DeviceIdentifier"] as? String == id,
                  StorageDiskSafety.assess(disk) == .externalPhysicalCandidate else {
                throw LabError.invalidDisk
            }
            let partitions = try StoragePartitionInspector.partitions(for: id)
            var matches: [(URL, String)] = []
            for part in partitions where part.id.range(of: "^" + id + "s[0-9]+$", options: .regularExpression) != nil {
                let volume = try diskInfo(part.id)
                guard volume["DeviceIdentifier"] as? String == part.id,
                      volume["ParentWholeDisk"] as? String == id,
                      volume["FilesystemName"] as? String == "MS-DOS FAT32",
                      let mount = volume["MountPoint"] as? String,
                      mount.hasPrefix("/Volumes/"),
                      let uuid = volume["VolumeUUID"] as? String, !uuid.isEmpty else { continue }
                let snapshot = try SakuraDiskIdentityGuard.capture(disk: disk, partition: volume)
                guard snapshot.mountPoint == mount else { throw LabError.invalidDisk }
                matches.append((URL(fileURLWithPath: mount, isDirectory: true), uuid))
            }
            guard matches.count == 1 else { throw LabError.invalidDisk }
            return matches[0]
        }
        let (source, sourceUUID) = try mountedFAT32(sourceDiskID)
        let (target, targetUUID) = try mountedFAT32(targetDiskID)
        guard sourceUUID != targetUUID,
              source.path != target.path else { throw LabError.invalidDisk }
        return Volumes(source: source, target: target, sourceUUID: sourceUUID, targetUUID: targetUUID)
    }

    static func sourceRoot(for diskID: String) throws -> URL {
        let volumes = try verifyDiskPairCandidate(diskID)
        return volumes
    }

    private static func verifyDiskPairCandidate(_ id: String) throws -> URL {
        guard id.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            throw LabError.invalidSource
        }
        let disk = try diskInfo(id)
        guard disk["DeviceIdentifier"] as? String == id,
              StorageDiskSafety.assess(disk) == .externalPhysicalCandidate else {
            throw LabError.invalidSource
        }
        let partitions = try StoragePartitionInspector.partitions(for: id)
        var mounts: [URL] = []
        for part in partitions where part.id.range(of: "^" + id + "s[0-9]+$", options: .regularExpression) != nil {
            let p = try diskInfo(part.id)
            guard p["DeviceIdentifier"] as? String == part.id,
                  p["ParentWholeDisk"] as? String == id,
                  p["FilesystemName"] as? String == "MS-DOS FAT32",
                  let mount = p["MountPoint"] as? String,
                  mount.hasPrefix("/Volumes/"),
                  (p["VolumeUUID"] as? String) != nil else { continue }
            _ = try SakuraDiskIdentityGuard.capture(disk: disk, partition: p)
            mounts.append(URL(fileURLWithPath: mount, isDirectory: true))
        }
        guard mounts.count == 1 else { throw LabError.invalidSource }
        return mounts[0]
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

    private static func prepareJournal(_ journal: URL) throws {
        try verifyDirectory(journal.deletingLastPathComponent())
        let fm = FileManager.default
        if !fm.fileExists(atPath: journal.path) {
            try fm.createDirectory(at: journal, withIntermediateDirectories: false)
        }
        try verifyDirectory(journal)
    }

    private static func previousCheckpoint(journal: URL, session: String) throws
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

    // Read-only, fail-closed conflict scan BEFORE creating target directories.
    // The full SakuraResumePreflight still runs after directory preparation.
    private static func preflightDestinationWithoutWriting(
        manifest: SakuraMigrationManifest.Report,
        checkpoint: SakuraTransferJournal.Checkpoint,
        destination: URL
    ) throws {
        guard manifest.complete else { throw LabError.invalidCheckpoint }
        let done = Set(checkpoint.files.map { $0.relativePath })
        for entry in manifest.entries {
            let relative = entry.relativePath
            let parts = relative.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") })
            else { throw LabError.invalidCheckpoint }

            var cursor = destination
            for (index, part) in parts.enumerated() {
                cursor.appendPathComponent(String(part))
                var info = stat()
                if lstat(cursor.path, &info) == 0 {
                    let kind = info.st_mode & mode_t(S_IFMT)
                    if index < parts.count - 1 || entry.kind == .directory {
                        guard kind == mode_t(S_IFDIR) else { throw LabError.invalidDisk }
                    } else {
                        // Previously verified destination files may exist only with a checkpoint.
                        guard done.contains(relative), kind == mode_t(S_IFREG) else {
                            throw LabError.invalidDisk
                        }
                    }
                } else {
                    guard errno == ENOENT else { throw LabError.invalidDisk }
                    // Missing ancestor: no destination file can exist below it.
                    break
                }
            }
        }
    }

    static func run(
        sourceDiskID: String,
        targetDiskID: String,
        approvedSkippedPaths: Set<String>,
        shouldStop: () -> Bool,
        onProgress: (SakuraResumableTransfer.Progress) -> Void,
        onFinalVerification: (Int, Int) -> Void = { _, _ in }
    ) throws -> SakuraResumableTransfer.Result {

        guard !shouldStop() else { throw LabError.cancelled }

        let initial = try verifyVolumes(sourceDiskID: sourceDiskID, targetDiskID: targetDiskID)
        let source = initial.source
        let destination = initial.target
        let sourceUUID = initial.sourceUUID
        let targetUUID = initial.targetUUID
        let session = sessionID(sourceUUID, targetUUID)
        let journal = journalBase.appendingPathComponent(session, isDirectory: true)
        // Never place a journal on either removable card.
        try FileManager.default.createDirectory(at: journalBase, withIntermediateDirectories: true)
        try prepareJournal(journal)

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
        let checkpoint = try previousCheckpoint(journal: journal, session: session)

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

        // Revalidate before preparing destination directories.
        let volumesBeforePreparation = try verifyVolumes(sourceDiskID: sourceDiskID, targetDiskID: targetDiskID)
        guard volumesBeforePreparation.sourceUUID == sourceUUID,
              volumesBeforePreparation.targetUUID == targetUUID,
              volumesBeforePreparation.source == source,
              volumesBeforePreparation.target == destination else {
            throw LabError.invalidDisk
        }

        // Check conflicts before the first write to the target card.
        try preflightDestinationWithoutWriting(
            manifest: preparation.manifest,
            checkpoint: checkpoint,
            destination: destination
        )

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

        let confirmed = try verifyVolumes(sourceDiskID: sourceDiskID, targetDiskID: targetDiskID)
        guard confirmed.sourceUUID == sourceUUID,
              confirmed.targetUUID == targetUUID,
              confirmed.source == source,
              confirmed.target == destination else {
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
                    let volumes = try verifyVolumes(sourceDiskID: sourceDiskID, targetDiskID: targetDiskID)
                    guard volumes.source == source && volumes.target == destination else { throw LabError.invalidDisk }
                    current = (volumes.sourceUUID, volumes.targetUUID)
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
            onProgress: onProgress,
            onFinalVerification: onFinalVerification
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
                return "Не подтверждена исходная физическая FAT32-карта."
            case .unsafeJournal:
                return "Каталог журнала отсутствует или содержит небезопасный путь."
            case .invalidCheckpoint:
                return "Контрольные точки сеанса повреждены или неполны."
            case .insufficientSpace:
                return "Недостаточно свободного места на целевой карте."
            case .cancelled:
                return "Остановлено до начала копирования."
            }
        }
    }
}
