import Foundation

/// Read-only geometry reported by macOS. Offsets and sizes are in bytes.
public struct StoragePartitionGeometry: Sendable, Equatable {
    public let identifier: String
    public let offsetBytes: UInt64
    public let sizeBytes: UInt64
    public let blockSizeBytes: UInt64

    /// Exclusive end: last valid byte is endExclusiveBytes - 1.
    public var endExclusiveBytes: UInt64? {
        let (end, overflow) = offsetBytes.addingReportingOverflow(sizeBytes)
        return overflow ? nil : end
    }

    public init?(identifier: String, offsetBytes: UInt64, sizeBytes: UInt64, blockSizeBytes: UInt64) {
        guard sizeBytes > 0, blockSizeBytes > 0 else { return nil }
        guard !offsetBytes.addingReportingOverflow(sizeBytes).overflow else { return nil }
        self.identifier = identifier
        self.offsetBytes = offsetBytes
        self.sizeBytes = sizeBytes
        self.blockSizeBytes = blockSizeBytes
    }
}

public enum StoragePartitionGeometryInspector {
    /// This API reads diskutil metadata. It never mounts, formats or writes a device.
    public static func inspect(partition identifier: String) throws -> StoragePartitionGeometry {
        guard identifier.range(of: #"^disk[0-9]+s[0-9]+$"#, options: .regularExpression) != nil else {
            throw error(1, "Некорректный идентификатор раздела")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["info", "-plist", identifier]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw error(2, "diskutil не смог прочитать информацию о разделе")
        }
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let info = plist as? [String: Any],
              let returnedID = info["DeviceIdentifier"] as? String,
              returnedID == identifier,
              let offset = uint64(info["PartitionMapPartitionOffset"]),
              let size = uint64(info["Size"]),
              let blockSize = uint64(info["DeviceBlockSize"]),
              let geometry = StoragePartitionGeometry(
                identifier: identifier,
                offsetBytes: offset,
                sizeBytes: size,
                blockSizeBytes: blockSize
              ) else {
            throw error(3, "Отсутствуют или некорректны параметры геометрии раздела")
        }
        return geometry
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        guard let n = value as? NSNumber else { return nil }
        let text = n.stringValue
        guard !text.hasPrefix("-") else { return nil }
        return UInt64(text)
    }

    private static func error(_ code: Int, _ message: String) -> NSError {
        NSError(domain: "SakuraStorage.Geometry", code: code,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
