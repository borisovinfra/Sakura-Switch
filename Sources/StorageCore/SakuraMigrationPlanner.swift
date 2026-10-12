import Foundation

/// Pure, read-only preflight for a proposed file-based SD migration.
/// All inputs must be measured and validated by the caller. No I/O or copying.
public enum SakuraMigrationPlanner {
    public enum Status: String, Sendable, Equatable {
        case blocked
        case needsMoreInformation
        case candidateForFurtherReview
    }

    public struct Input: Sendable {
        public let sourceDiskID: String
        public let targetDiskID: String
        public let sourceVerifiedExternalPhysical: Bool
        public let targetVerifiedExternalPhysical: Bool
        public let sourceAndTargetVolumesVerified: Bool
        public let sourceFileBasedStructureVerified: Bool
        /// Total bytes of all files selected for migration, not only emuMMC.
        public let requiredBytes: UInt64?
        /// Available bytes reported for the specific target volume.
        public let targetAvailableBytes: UInt64?
        /// Additional user/caller-specified buffer; never silently defaulted.
        public let reserveBytes: UInt64?
        /// True only when a separate inspection confirms no conflicting target files.
        public let targetConflictsAbsent: Bool?

        public init(sourceDiskID: String, targetDiskID: String,
                    sourceVerifiedExternalPhysical: Bool, targetVerifiedExternalPhysical: Bool,
                    sourceAndTargetVolumesVerified: Bool, sourceFileBasedStructureVerified: Bool,
                    requiredBytes: UInt64?, targetAvailableBytes: UInt64?,
                    reserveBytes: UInt64?, targetConflictsAbsent: Bool?) {
            self.sourceDiskID = sourceDiskID
            self.targetDiskID = targetDiskID
            self.sourceVerifiedExternalPhysical = sourceVerifiedExternalPhysical
            self.targetVerifiedExternalPhysical = targetVerifiedExternalPhysical
            self.sourceAndTargetVolumesVerified = sourceAndTargetVolumesVerified
            self.sourceFileBasedStructureVerified = sourceFileBasedStructureVerified
            self.requiredBytes = requiredBytes
            self.targetAvailableBytes = targetAvailableBytes
            self.reserveBytes = reserveBytes
            self.targetConflictsAbsent = targetConflictsAbsent
        }
    }

    public struct Report: Sendable, Equatable {
        public let status: Status
        public let messages: [String]
        public let minimumAvailableBytes: UInt64?
    }

    public static func assess(_ input: Input) -> Report {
        func result(_ status: Status, _ message: String, required: UInt64? = nil) -> Report {
            Report(status: status, messages: [message], minimumAvailableBytes: required)
        }
        let pattern = #"^disk[0-9]+$"#
        guard input.sourceDiskID.range(of: pattern, options: .regularExpression) != nil,
              input.targetDiskID.range(of: pattern, options: .regularExpression) != nil else {
            return result(.blocked, "Некорректный идентификатор физического диска")
        }
        guard input.sourceDiskID != input.targetDiskID else {
            return result(.blocked, "Источник и назначение — один физический диск")
        }
        guard input.sourceVerifiedExternalPhysical && input.targetVerifiedExternalPhysical else {
            return result(.blocked, "Один из физических дисков не прошёл проверку безопасности")
        }
        guard input.sourceAndTargetVolumesVerified else {
            return result(.needsMoreInformation, "Не подтверждена принадлежность томов выбранным дискам")
        }
        guard input.sourceFileBasedStructureVerified else {
            return result(.needsMoreInformation, "Структура файловой emuMMC ещё не подтверждена")
        }
        guard let bytes = input.requiredBytes, bytes > 0,
              let free = input.targetAvailableBytes,
              let reserve = input.reserveBytes else {
            return result(.needsMoreInformation, "Неизвестен полный объём переноса, свободное место или резерв")
        }
        let (needed, overflow) = bytes.addingReportingOverflow(reserve)
        guard !overflow else {
            return result(.blocked, "Переполнение при расчёте объёма и резерва")
        }
        guard free >= needed else {
            return result(.blocked, "На целевом томе недостаточно свободного места", required: needed)
        }
        guard let conflictsAbsent = input.targetConflictsAbsent else {
            return result(.needsMoreInformation, "Не проверено наличие конфликтующих файлов на цели", required: needed)
        }
        guard conflictsAbsent else {
            return result(.blocked, "На целевом томе есть конфликтующие файлы", required: needed)
        }
        return result(.candidateForFurtherReview,
                      "Предварительные условия соблюдены; перед копированием нужны повторная проверка дисков, полный манифест, стратегия проверки и восстановления",
                      required: needed)
    }
}
