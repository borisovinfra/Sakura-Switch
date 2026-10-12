import Foundation

/// Coordinates existing read-only validators. This is not a NAND integrity or migration check.
public enum SakuraStorageDiagnostic {
    public enum Status: String, Sendable, Equatable {
        case structurePresent
        case incomplete
        case invalid
        case needsMoreInformation
        case disabled
    }

    public struct Report: Sendable {
        public let mode: SakuraEmuMMCDetector.Mode
        public let status: Status
        public let messages: [String]
    }

    /// Pass only the inputs relevant to the selected emuMMC mode.
    /// gppSectors must be measured/verified independently, never guessed.
    public static func inspect(
        configuration: SakuraEmuMMCDetector.Result,
        sdRoot: URL? = nil,
        rawPartition: StoragePartitionGeometry? = nil,
        gppSectors: UInt64? = nil
    ) -> Report {
        func report(_ status: Status, _ explanation: String) -> Report {
            Report(mode: configuration.mode, status: status,
                   messages: configuration.warnings + [explanation])
        }
        switch configuration.mode {
        case .disabled:
            return report(.disabled, "emuMMC отключена в конфигурации")
        case .unknown:
            return report(.needsMoreInformation, "Тип emuMMC не определён")
        case .fileBased:
            guard let sdRoot else {
                return report(.needsMoreInformation, "Для проверки файловой emuMMC нужен корень SD-карты")
            }
            let result = SakuraStorageValidator.inspectFileBased(sdRoot: sdRoot, configuration: configuration)
            let status: Status
            switch result.status {
            case .structurePresent: status = .structurePresent
            case .incomplete: status = .incomplete
            case .notApplicable, .unknown: status = .needsMoreInformation
            }
            return Report(mode: configuration.mode, status: status,
                          messages: configuration.warnings + result.messages +
                            ["Проверена только структура файлов, не целостность NAND"])
        case .partitionBased:
            guard let rawPartition else {
                return report(.needsMoreInformation, "Для RAW emuMMC необходима геометрия раздела")
            }
            guard let gppSectors else {
                let base = SakuraRAWValidator.assess(sector: configuration.sector, partition: rawPartition)
                switch base.verdict {
                case .candidateWithinPartition:
                    return report(.needsMoreInformation, "Начальный сектор находится в разделе; необходим подтверждённый размер GPP")
                case .outsidePartition:
                    return report(.invalid, base.reason)
                case .invalidInput:
                    return report(.invalid, base.reason)
                }
            }
            let layout = SakuraRAWLayoutValidator.assess(
                sector: configuration.sector, gppSectors: gppSectors, partition: rawPartition)
            switch layout.verdict {
            case .fitsWithinPartition:
                return report(.structurePresent, "Области BOOT0/BOOT1/GPP помещаются в раздел; содержимое NAND не проверено")
            case .outsidePartition, .invalidInput:
                return report(.invalid, layout.reason)
            }
        }
    }
}
