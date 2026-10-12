import Foundation

/// Compares two read-only diskutil metadata snapshots. Matching metadata is NOT
/// proof of physical identity and never authorizes a write or a migration.
public enum SakuraDiskIdentityGuard {
    public enum Failure: Error {
        case invalidDisk, invalidPartition, missingMetadata
    }

    public struct Snapshot: Sendable, Equatable {
        public let diskID: String
        public let partitionID: String
        public let diskSize: UInt64
        public let partitionSize: UInt64
        public let volumeSize: UInt64
        public let mediaName: String
        public let busProtocol: String
        public let mountPoint: String
        public let volumeName: String
        public let filesystem: String
        public let diskUUID: String?
        public let volumeUUID: String?
    }

    public enum Assessment: Sendable, Equatable {
        case metadataConsistentIdentityUnproven
        case changed
    }

    /// Both dictionaries must come from freshly retrieved diskutil info -plist.
    /// Only one selected, mounted partition is represented per snapshot.
    public static func capture(disk: [String: Any], partition: [String: Any]) throws -> Snapshot {
        guard case .externalPhysicalCandidate = StorageDiskSafety.assess(disk),
              let id = disk["DeviceIdentifier"] as? String,
              let diskSize = (disk["Size"] as? NSNumber)?.uint64Value,
              diskSize > 0 else { throw Failure.invalidDisk }

        guard let partitionID = partition["DeviceIdentifier"] as? String,
              partitionID.range(of: "^" + id + "s[0-9]+$", options: .regularExpression) != nil,
              partition["ParentWholeDisk"] as? String == id,
              let partSize = (partition["Size"] as? NSNumber)?.uint64Value,
              partSize > 0, partSize <= diskSize,
              let volumeSize = (partition["TotalSize"] as? NSNumber)?.uint64Value,
              volumeSize > 0, volumeSize <= partSize else { throw Failure.invalidPartition }

        guard let media = disk["MediaName"] as? String, !media.isEmpty,
              let bus = disk["BusProtocol"] as? String, !bus.isEmpty,
              let mount = partition["MountPoint"] as? String,
              mount.hasPrefix("/Volumes/"), mount.count > "/Volumes/".count,
              !mount.contains("/../"), !mount.hasSuffix("/.."),
              let name = partition["VolumeName"] as? String, !name.isEmpty,
              let fs = partition["FilesystemName"] as? String, !fs.isEmpty else {
            throw Failure.missingMetadata
        }

        func uuid(_ key: String) -> String? {
            guard let text = partition[key] as? String, !text.isEmpty else { return nil }
            return text.uppercased()
        }
        let diskUUID = uuid("DiskUUID")
        let volumeUUID = uuid("VolumeUUID")
        guard diskUUID != nil || volumeUUID != nil else { throw Failure.missingMetadata }

        return Snapshot(diskID: id, partitionID: partitionID,
                        diskSize: diskSize, partitionSize: partSize, volumeSize: volumeSize,
                        mediaName: media, busProtocol: bus,
                        mountPoint: mount, volumeName: name, filesystem: fs,
                        diskUUID: diskUUID, volumeUUID: volumeUUID)
    }

    /// The caller must invalidate its UI state on detach/refresh, even if a
    /// later snapshot compares equal. Device identifiers may be recycled.
    public static func assess(previous: Snapshot, current: Snapshot) -> Assessment {
        previous == current ? .metadataConsistentIdentityUnproven : .changed
    }
}
