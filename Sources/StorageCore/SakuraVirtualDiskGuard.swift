import Foundation

/// Authorizes only a mounted disk image belonging to SakuraMigrationLab.
/// This guard never authorizes writing to a physical disk.
public enum SakuraVirtualDiskGuard {

    public enum Failure: Error {
        case imageNotFound
        case ambiguousDevice
        case unsafeDevice
        case wrongVolume
    }

    public static func verify(imagePath: String, volumePath: String) throws {
        let image = URL(fileURLWithPath: imagePath).standardizedFileURL

        guard image.lastPathComponent == "SakuraVirtualSD.sparseimage",
              image.path.contains("/.storage-tests/SakuraMigrationLab/") else {
            throw Failure.imageNotFound
        }

        let infoProcess = Process()
        infoProcess.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        infoProcess.arguments = ["info", "-plist"]

        let output = Pipe()
        infoProcess.standardOutput = output
        infoProcess.standardError = FileHandle.nullDevice

        try infoProcess.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        infoProcess.waitUntilExit()

        guard infoProcess.terminationStatus == 0,
              let plist = try PropertyListSerialization.propertyList(
                from: data, format: nil
              ) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            throw Failure.imageNotFound
        }

        let matches = images.filter {
            ($0["image-path"] as? String) == image.path
        }

        guard matches.count == 1,
              let entities = matches[0]["system-entities"] as? [[String: Any]] else {
            throw Failure.imageNotFound
        }

        let devices = entities.compactMap {
            $0["dev-entry"] as? String
        }.filter {
            $0.range(of: "^/dev/disk[0-9]+$", options: .regularExpression) != nil
        }

        guard devices.count == 1 else {
            throw Failure.ambiguousDevice
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", volumePath]

        let volumeOutput = Pipe()
        process.standardOutput = volumeOutput
        process.standardError = FileHandle.nullDevice

        try process.run()
        let volumeData = volumeOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let volume = try PropertyListSerialization.propertyList(
                from: volumeData, format: nil
              ) as? [String: Any] else {
            throw Failure.wrongVolume
        }

        let diskID = URL(fileURLWithPath: devices[0]).lastPathComponent

        let diskProcess = Process()
        diskProcess.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        diskProcess.arguments = ["info", "-plist", diskID]

        let diskOutput = Pipe()
        diskProcess.standardOutput = diskOutput
        diskProcess.standardError = FileHandle.nullDevice

        try diskProcess.run()
        let diskData = diskOutput.fileHandleForReading.readDataToEndOfFile()
        diskProcess.waitUntilExit()

        guard diskProcess.terminationStatus == 0,
              let disk = try PropertyListSerialization.propertyList(
                from: diskData, format: nil
              ) as? [String: Any],
              disk["DeviceIdentifier"] as? String == diskID,
              disk["VirtualOrPhysical"] as? String == "Virtual",
              disk["BusProtocol"] as? String == "Disk Image",
              disk["Content"] as? String == "FDisk_partition_scheme",
              disk["WholeDisk"] as? Bool == true,
              (disk["Size"] as? NSNumber)?.uint64Value == 68_719_476_736,
              volume["DeviceIdentifier"] as? String == diskID + "s1",
              volume["ParentWholeDisk"] as? String == diskID,
              volume["WholeDisk"] as? Bool == false,
              volume["MountPoint"] as? String == "/Volumes/SAKURASD",
              volumePath == "/Volumes/SAKURASD",
              volume["FilesystemName"] as? String == "MS-DOS FAT32",
              volume["VolumeUUID"] as? String ==
                "E84B56CE-738D-3BB4-8B0C-A0E1392B74D7" else {
            throw Failure.unsafeDevice
        }
    }
}
