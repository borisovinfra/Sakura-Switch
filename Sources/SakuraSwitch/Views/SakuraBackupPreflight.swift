import Foundation
import StorageCore

struct SakuraBackupPreflightResult: Sendable {
    let sourceName: String
    let fileCount: Int
    let requiredBytes: UInt64
    let availableBytes: UInt64
    let skippedPaths: [String]
}

enum SakuraBackupPreflight {
    static func inspect(
        diskID: String,
        destination: URL
    ) throws -> SakuraBackupPreflightResult {
        let source = try SakuraPhysicalMigrationEngine.sourceRoot(for: diskID)

        try SakuraBackupSafety.validate(
            sourceRoot: source,
            destinationFolder: destination
        )

        let manifest = SakuraMigrationManifest.inspect(
            root: source, policy: .excludeKnownMacOSMetadata
        )
        guard manifest.complete else {
            throw NSError(domain: "SakuraBackup", code: 3,
                userInfo: [NSLocalizedDescriptionKey:
                    manifest.errors.prefix(3).joined(separator: "; ")])
        }
        let preparation = try SakuraFileMigrationRunner.inspect(
            sourceRoot: source,
            approvedSkippedPaths: Set(manifest.skippedPaths)
        )

        let values = try destination.resourceValues(
            forKeys: [.volumeAvailableCapacityKey]
        )

        guard let available = values.volumeAvailableCapacity,
              available >= 0 else {
            throw NSError(
                domain: "SakuraBackup",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey:
                    "Не удалось определить свободное место."]
            )
        }

        let required = preparation.requiredBytes
        let (minimum, overflow) =
            required.addingReportingOverflow(1_073_741_824)

        guard !overflow, UInt64(available) >= minimum else {
            throw NSError(
                domain: "SakuraBackup",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey:
                    "Недостаточно места для резервной копии с запасом 1 ГБ."]
            )
        }

        return SakuraBackupPreflightResult(
            sourceName: source.lastPathComponent,
            fileCount: preparation.manifest.fileCount,
            requiredBytes: required,
            availableBytes: UInt64(available),
            skippedPaths: manifest.skippedPaths
        )
    }
}
