import Foundation

/// Pure, read-only synthesis of migration checks. Never authorizes any write.
public enum SakuraMigrationReadiness {
    public enum Status: String, Sendable, Equatable {
        case blocked
        case needsMoreInformation
        case candidateForFurtherReview
    }

    public struct Input: Sendable {
        public let planner: SakuraMigrationPlanner.Input
        /// True only when every omitted path has been independently reviewed.
        public let excludedPathsReviewed: Bool
        /// A complete source inventory (including its omissions) was validated.
        public let inventoryComplete: Bool

        public init(planner: SakuraMigrationPlanner.Input,
                    excludedPathsReviewed: Bool,
                    inventoryComplete: Bool) {
            self.planner = planner
            self.excludedPathsReviewed = excludedPathsReviewed
            self.inventoryComplete = inventoryComplete
        }
    }

    public struct Report: Sendable, Equatable {
        public let status: Status
        public let messages: [String]
        public let minimumRequiredBytes: UInt64?
        /// This diagnostic component never authorizes copying or formatting.
        public var writesAuthorized: Bool { false }
    }

    public static func assess(_ input: Input) -> Report {
        let plan = input.planner
        func result(_ status: Status, _ message: String, _ needed: UInt64? = nil) -> Report {
            Report(status: status, messages: [message], minimumRequiredBytes: needed)
        }
        let pattern = #"^disk[0-9]+$"#
        guard plan.sourceDiskID.range(of: pattern, options: .regularExpression) != nil,
              plan.targetDiskID.range(of: pattern, options: .regularExpression) != nil else {
            return result(.blocked, "Некорректный идентификатор физического диска")
        }
        guard plan.sourceDiskID != plan.targetDiskID else {
            return result(.blocked, "Источник и назначение — один физический диск")
        }
        guard plan.sourceVerifiedExternalPhysical && plan.targetVerifiedExternalPhysical else {
            return result(.blocked, "Безопасность физических дисков не подтверждена")
        }
        guard plan.sourceAndTargetVolumesVerified else {
            return result(.needsMoreInformation, "Принадлежность томов выбранным дискам не подтверждена")
        }
        guard input.inventoryComplete else {
            return result(.needsMoreInformation, "Инвентаризация источника не завершена")
        }

        // A known deficit is conclusive even if reserve or other details remain unknown.
        if let bytes = plan.requiredBytes, bytes > 0,
           let free = plan.targetAvailableBytes, bytes > free {
            return result(.blocked, "Недостаточно места для файлов: не хватает минимум \(bytes - free) байт без учёта резерва", bytes)
        }
        // A known conflict is also conclusive, even when the reserve is unknown.
        if plan.targetConflictsAbsent == false {
            return result(.blocked, "На целевом томе обнаружены конфликтующие файлы")
        }
        guard input.excludedPathsReviewed else {
            return result(.needsMoreInformation, "Исключённые пути требуют отдельной проверки")
        }

        let checked = SakuraMigrationPlanner.assess(plan)
        switch checked.status {
        case .blocked:
            return Report(status: .blocked, messages: checked.messages,
                          minimumRequiredBytes: checked.minimumAvailableBytes)
        case .needsMoreInformation:
            return Report(status: .needsMoreInformation, messages: checked.messages,
                          minimumRequiredBytes: checked.minimumAvailableBytes)
        case .candidateForFurtherReview:
            return Report(status: .candidateForFurtherReview, messages: checked.messages +
                ["Это только предварительная оценка. Запись и форматирование не разрешены."],
                minimumRequiredBytes: checked.minimumAvailableBytes)
        }
    }
}
