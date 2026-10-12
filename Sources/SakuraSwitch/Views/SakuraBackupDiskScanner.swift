import Foundation
import StorageCore

struct SakuraBackupDisk: Identifiable, Sendable {
    let id: String
    let name: String
    let size: UInt64
}

enum SakuraBackupDiskScanner {
    static func scan() throws -> [SakuraBackupDisk] {
        var result: [SakuraBackupDisk] = []

        for disk in try StorageInspector.externalDisks() {
            guard disk.id.range(
                of: #"^disk[0-9]+$"#,
                options: .regularExpression
            ) != nil else { continue }

            let root = try SakuraPhysicalMigrationEngine.sourceRoot(for: disk.id)
            let name = root.lastPathComponent

            result.append(SakuraBackupDisk(
                id: disk.id,
                name: name,
                size: disk.size
            ))
        }

        return result
    }
}
