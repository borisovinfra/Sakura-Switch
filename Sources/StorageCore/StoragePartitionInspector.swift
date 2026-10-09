import Foundation

/// Read-only partition metadata supplied by macOS diskutil.
public struct StoragePartition: Sendable, Identifiable {
    public let id: String
    public let content: String
    public let size: UInt64
    public let volumeName: String?

    public init(id: String, content: String, size: UInt64, volumeName: String?) {
        self.id = id
        self.content = content
        self.size = size
        self.volumeName = volumeName
    }
}

/// Reads partition layout only. Never mounts, formats, or writes to a disk.
public enum StoragePartitionInspector {
    public static func partitions(for disk: String) throws -> [StoragePartition] {
        guard disk.range(of: #"^disk[0-9]+$"#, options: .regularExpression) != nil else {
            throw inspectionError(1, "Некорректный идентификатор диска")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["list", "-plist", disk]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw inspectionError(2, "Не удалось прочитать таблицу разделов")
        }

        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let root = plist as? [String: Any],
              let entries = root["AllDisksAndPartitions"] as? [[String: Any]],
              let entry = entries.first(where: { $0["DeviceIdentifier"] as? String == disk }),
              let parts = entry["Partitions"] as? [[String: Any]] else {
            throw inspectionError(3, "Неизвестный формат данных о разделах")
        }

        return parts.compactMap { part in
            guard let id = part["DeviceIdentifier"] as? String,
                  let size = part["Size"] as? NSNumber else { return nil }
            return StoragePartition(
                id: id,
                content: part["Content"] as? String ?? "Unknown",
                size: size.uint64Value,
                volumeName: part["VolumeName"] as? String
            )
        }
    }

    private static func inspectionError(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "SakuraStorage.Partitions", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
