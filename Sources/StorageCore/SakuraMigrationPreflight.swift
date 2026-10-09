import Foundation

/// Pure bridge between a completed inventory and MigrationPlanner.
/// All identity, space, structure and conflict facts are caller-supplied,
/// NOT established by this component. No filesystem I/O or copying.
public enum SakuraMigrationPreflight {
    public struct Context: Sendable {
        public let sourceDiskID: String
        public let targetDiskID: String
        public let sourceVerifiedExternalPhysical: Bool
        public let targetVerifiedExternalPhysical: Bool
        public let sourceAndTargetVolumesVerified: Bool
        public let sourceFileBasedStructureVerified: Bool
        public let targetAvailableBytes: UInt64?
        public let reserveBytes: UInt64?
        public let targetConflictsAbsent: Bool?
        /// Caller must explicitly review EVERY omitted path, including directories.
        public let excludedPathsReviewed: Bool
        /// A fresh external revalidation is required before any actual copy.
        public init(sourceDiskID: String, targetDiskID: String,
                    sourceVerifiedExternalPhysical: Bool,
                    targetVerifiedExternalPhysical: Bool,
                    sourceAndTargetVolumesVerified: Bool,
                    sourceFileBasedStructureVerified: Bool,
                    targetAvailableBytes: UInt64?, reserveBytes: UInt64?,
                    targetConflictsAbsent: Bool?, excludedPathsReviewed: Bool) {
            self.sourceDiskID = sourceDiskID
            self.targetDiskID = targetDiskID
            self.sourceVerifiedExternalPhysical = sourceVerifiedExternalPhysical
            self.targetVerifiedExternalPhysical = targetVerifiedExternalPhysical
            self.sourceAndTargetVolumesVerified = sourceAndTargetVolumesVerified
            self.sourceFileBasedStructureVerified = sourceFileBasedStructureVerified
            self.targetAvailableBytes = targetAvailableBytes
            self.reserveBytes = reserveBytes
            self.targetConflictsAbsent = targetConflictsAbsent
            self.excludedPathsReviewed = excludedPathsReviewed
        }
    }

    public struct Report: Sendable, Equatable {
        public let status: SakuraMigrationPlanner.Status
        public let messages: [String]
        public let inventoryBytes: UInt64?
        public let minimumAvailableBytes: UInt64?
        public let excludedPaths: [String]
    }

    public static func assess(inventory: SakuraMigrationInventory.Report,
                              context: Context) -> Report {
        func stop(_ status: SakuraMigrationPlanner.Status, _ message: String) -> Report {
            Report(status: status, messages: [message],
                   inventoryBytes: inventory.totalLogicalBytes,
                   minimumAvailableBytes: nil, excludedPaths: inventory.skippedPaths)
        }
        guard inventory.complete else {
            return stop(.blocked, "Инвентаризация неполная: \(inventory.errors.joined(separator: "; "))")
        }
        guard let bytes = inventory.totalLogicalBytes, bytes > 0 else {
            return stop(.needsMoreInformation, "Неизвестен или равен нулю полный размер файлов")
        }
        if !inventory.skippedPaths.isEmpty && !context.excludedPathsReviewed {
            return stop(.needsMoreInformation,
                        "Не подтверждены исключённые из инвентаризации пути")
        }
        let input = SakuraMigrationPlanner.Input(
            sourceDiskID: context.sourceDiskID, targetDiskID: context.targetDiskID,
            sourceVerifiedExternalPhysical: context.sourceVerifiedExternalPhysical,
            targetVerifiedExternalPhysical: context.targetVerifiedExternalPhysical,
            sourceAndTargetVolumesVerified: context.sourceAndTargetVolumesVerified,
            sourceFileBasedStructureVerified: context.sourceFileBasedStructureVerified,
            requiredBytes: bytes, targetAvailableBytes: context.targetAvailableBytes,
            reserveBytes: context.reserveBytes,
            targetConflictsAbsent: context.targetConflictsAbsent)
        let plan = SakuraMigrationPlanner.assess(input)
        return Report(status: plan.status, messages: plan.messages,
                      inventoryBytes: bytes, minimumAvailableBytes: plan.minimumAvailableBytes,
                      excludedPaths: inventory.skippedPaths)
    }
}
