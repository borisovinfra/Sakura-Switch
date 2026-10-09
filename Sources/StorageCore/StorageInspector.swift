import Foundation

public struct StorageDisk: Sendable, Identifiable {
    public let id: String
    public let size: UInt64
    public let partitionScheme: String

    public init(
        id: String,
        size: UInt64,
        partitionScheme: String
    ) {
        self.id = id
        self.size = size
        self.partitionScheme = partitionScheme
    }
}

public enum StorageInspector {

    public static func externalDisks() throws -> [StorageDisk] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        process.arguments = ["list", "-plist", "external", "physical"]

        let output = Pipe()
        process.standardOutput = output

        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "SakuraStorage",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Не удалось получить список накопителей"
                ]
            )
        }

        let plist = try PropertyListSerialization.propertyList(
            from: data,
            format: nil
        )

        guard
            let root = plist as? [String: Any],
            let entries = root["AllDisksAndPartitions"]
                as? [[String: Any]]
        else {
            throw NSError(
                domain: "SakuraStorage",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Неожиданный формат ответа diskutil"
                ]
            )
        }

        return entries.compactMap { entry in
            guard
                let id = entry["DeviceIdentifier"] as? String,
                let size = entry["Size"] as? NSNumber
            else {
                return nil
            }

            return StorageDisk(
                id: id,
                size: size.uint64Value,
                partitionScheme: entry["Content"] as? String
                    ?? "Unknown"
            )
        }
    }
}
