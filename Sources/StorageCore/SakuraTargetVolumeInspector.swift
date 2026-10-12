import Foundation

/// Pure, read-only assessment of independently collected target-volume facts.
/// The caller MUST revalidate diskutil identity, mounting, free space and conflicts.
/// This module performs no disk or filesystem I/O, no mounting and no copying.
public enum SakuraTargetVolumeInspector {
    public enum Status: String, Sendable, Equatable {
        case blocked
        case needsMoreInformation
        case candidateForFurtherReview
    }

    public struct Snapshot: Sendable {
        public let diskID: String
        public let partitionID: String
        public let parentWholeDiskID: String?
        public let wholeDiskSafetyConfirmed: Bool
        public let mountPoint: String?
        public let mountPointVerified: Bool
        public let filesystemName: String?
        public let availableBytes: UInt64?
        public let availableBytesVerifiedForVolume: Bool
        public let targetConflictsAbsent: Bool?

        public init(diskID: String, partitionID: String, parentWholeDiskID: String?,
                    wholeDiskSafetyConfirmed: Bool, mountPoint: String?,
                    mountPointVerified: Bool, filesystemName: String?,
                    availableBytes: UInt64?, availableBytesVerifiedForVolume: Bool,
                    targetConflictsAbsent: Bool?) {
            self.diskID = diskID
            self.partitionID = partitionID
            self.parentWholeDiskID = parentWholeDiskID
            self.wholeDiskSafetyConfirmed = wholeDiskSafetyConfirmed
            self.mountPoint = mountPoint
            self.mountPointVerified = mountPointVerified
            self.filesystemName = filesystemName
            self.availableBytes = availableBytes
            self.availableBytesVerifiedForVolume = availableBytesVerifiedForVolume
            self.targetConflictsAbsent = targetConflictsAbsent
        }
    }

    public struct Report: Sendable, Equatable {
        public let status: Status
        public let messages: [String]
        public let verifiedAvailableBytes: UInt64?
        public let conflictsAbsent: Bool?
    }

    public static func assess(_ input: Snapshot) -> Report {
        func result(_ status: Status, _ message: String,
                    free: UInt64? = nil, conflicts: Bool? = nil) -> Report {
            Report(status: status, messages: [message],
                   verifiedAvailableBytes: free, conflictsAbsent: conflicts)
        }
        guard input.diskID.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil,
              input.partitionID.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil,
              input.partitionID.hasPrefix(input.diskID + "s") else {
            return result(.blocked, "Некорректная или несогласованная идентификация диска и раздела")
        }
        guard input.wholeDiskSafetyConfirmed else {
            return result(.blocked, "Физический целевой диск не прошёл проверку безопасности")
        }
        guard let parent = input.parentWholeDiskID else {
            return result(.needsMoreInformation, "Не установлен родительский физический диск тома")
        }
        guard parent == input.diskID else {
            return result(.blocked, "Том принадлежит другому физическому диску")
        }
        guard input.mountPointVerified,
              let mount = input.mountPoint,
              mount.hasPrefix("/Volumes/"),
              mount.count > "/Volumes/".count,
              !mount.contains("/../"), !mount.hasSuffix("/..") else {
            return result(.needsMoreInformation, "Точка монтирования не подтверждена")
        }
        guard let filesystem = input.filesystemName, !filesystem.isEmpty else {
            return result(.needsMoreInformation, "Не определена файловая система назначения")
        }
        // Conservative first implementation; other formats require separate review.
        guard filesystem == "MS-DOS FAT32" else {
            return result(.blocked, "Для этого сценария подтверждена только FAT32; файловая система: \(filesystem)")
        }
        guard input.availableBytesVerifiedForVolume, let available = input.availableBytes else {
            return result(.needsMoreInformation, "Свободное место не подтверждено для выбранного тома")
        }
        guard let noConflicts = input.targetConflictsAbsent else {
            return result(.needsMoreInformation, "Наличие конфликтующих файлов не проверено",
                          free: available)
        }
        guard noConflicts else {
            return result(.blocked, "На целевом томе обнаружены конфликтующие файлы",
                          free: available, conflicts: false)
        }
        return result(.candidateForFurtherReview,
                      "Метаданные тома предварительно согласованы; перед переносом необходима повторная проверка",
                      free: available, conflicts: true)
    }
}
