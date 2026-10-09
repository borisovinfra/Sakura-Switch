import Foundation
#if os(macOS)
import Darwin
#endif

/// Read-only bridge between diskutil and SakuraTargetVolumeInspector.
/// Never assumes that a mounted target has no file conflicts.
public enum SakuraTargetVolumeProbe {
    public enum ProbeError: Error, LocalizedError {
        case invalidIdentifier
        case unsupportedPlatform
        case diskutilFailed(String)
        case invalidMetadata(String)

        public var errorDescription: String? {
            switch self {
            case .invalidIdentifier: return "Некорректный идентификатор диска или раздела"
            case .unsupportedPlatform: return "Проверка доступна только на macOS"
            case .diskutilFailed(let message), .invalidMetadata(let message): return message
            }
        }
    }

    /// Pure assembly of a snapshot from separately measured facts.
    /// Conflicts are intentionally UNKNOWN: no manifest comparison is performed here.
    public static func assemble(
        diskID: String,
        partitionID: String,
        diskInfo: [String: Any],
        partitionInfo: [String: Any],
        mountedDeviceConfirmed: Bool,
        independentlyMeasuredFreeBytes: UInt64?
    ) -> SakuraTargetVolumeInspector.Snapshot {
        let safe: Bool
        if case .externalPhysicalCandidate = StorageDiskSafety.assess(diskInfo),
           diskInfo["DeviceIdentifier"] as? String == diskID {
            safe = true
        } else {
            safe = false
        }
        let partitionMatches = partitionInfo["DeviceIdentifier"] as? String == partitionID
        let parent = partitionMatches ? partitionInfo["ParentWholeDisk"] as? String : nil
        let mount = partitionMatches ? partitionInfo["MountPoint"] as? String : nil
        let fs = partitionMatches ? partitionInfo["FilesystemName"] as? String : nil
        let diskutilFree: UInt64?
        if let number = partitionInfo["FreeSpace"] as? NSNumber, number.int64Value >= 0 {
            diskutilFree = number.uint64Value
        } else {
            diskutilFree = nil
        }
        let verifiedMount = partitionMatches && mountedDeviceConfirmed && parent == diskID && mount != nil
        let available: UInt64? = verifiedMount ? independentlyMeasuredFreeBytes.flatMap { measured in
            diskutilFree.map { min($0, measured) }
        } : nil
        return SakuraTargetVolumeInspector.Snapshot(
            diskID: diskID, partitionID: partitionID,
            parentWholeDiskID: parent, wholeDiskSafetyConfirmed: safe,
            mountPoint: mount, mountPointVerified: verifiedMount,
            filesystemName: fs, availableBytes: available,
            availableBytesVerifiedForVolume: available != nil,
            targetConflictsAbsent: nil
        )
    }

    /// Real probe. Caller must independently ensure diskID is NOT the source disk.
    public static func inspect(diskID: String, partitionID: String) throws -> SakuraTargetVolumeInspector.Report {
        guard diskID.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              partitionID.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
              partitionID.hasPrefix(diskID + "s") else { throw ProbeError.invalidIdentifier }
#if os(macOS)
        let disk = try diskutilInfo(diskID)
        let partition = try diskutilInfo(partitionID)
        let mount = partition["MountPoint"] as? String
        var confirmed = false
        var measured: UInt64?
        if let mount, mount.hasPrefix("/Volumes/"), !mount.contains("/../") {
            var info = statfs()
            if statfs(mount, &info) == 0 {
                let mountedAt = withUnsafeBytes(of: info.f_mntonname) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                let mountedFrom = withUnsafeBytes(of: info.f_mntfromname) { raw in
                    String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                }
                confirmed = mountedAt == mount && mountedFrom == "/dev/" + partitionID
                if confirmed {
                    let (available, overflow) = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_bsize))
                    if !overflow { measured = available }
                }
            }
        }
        return SakuraTargetVolumeInspector.assess(assemble(
            diskID: diskID, partitionID: partitionID,
            diskInfo: disk, partitionInfo: partition,
            mountedDeviceConfirmed: confirmed,
            independentlyMeasuredFreeBytes: measured
        ))
#else
        throw ProbeError.unsupportedPlatform
#endif
    }

#if os(macOS)
    private static func diskutilInfo(_ identifier: String) throws -> [String: Any] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", identifier]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ProbeError.diskutilFailed("Не удалось прочитать diskutil info для \(identifier)")
        }
        guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw ProbeError.invalidMetadata("Неизвестный формат plist для \(identifier)")
        }
        return info
    }
#endif
}
