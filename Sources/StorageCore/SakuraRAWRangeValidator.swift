import Foundation

/// Pure arithmetic check of a caller-supplied RAW emuMMC byte range.
/// This does not infer NAND size, inspect storage, or prove bootability.
public enum SakuraRAWRangeValidator {
    public enum Verdict: String, Sendable, Equatable {
        case fitsWithinPartition
        case outsidePartition
        case invalidInput
    }

    public struct Assessment: Sendable, Equatable {
        public let verdict: Verdict
        public let startBytes: UInt64?
        public let endExclusiveBytes: UInt64?
        public let reason: String
    }

    /// `requiredBytes` must be independently established for the actual RAW
    /// layout. No default NAND size is assumed.
    public static func assess(
        sector: UInt64?,
        requiredBytes: UInt64,
        partition: StoragePartitionGeometry
    ) -> Assessment {
        guard let sector, sector > 0, requiredBytes > 0 else {
            return Assessment(verdict: .invalidInput, startBytes: nil,
                              endExclusiveBytes: nil,
                              reason: "Не указан начальный сектор или размер RAW emuMMC")
        }
        let (start, startOverflow) = sector.multipliedReportingOverflow(by: SakuraRAWValidator.sectorSizeBytes)
        guard !startOverflow else {
            return Assessment(verdict: .invalidInput, startBytes: nil,
                              endExclusiveBytes: nil,
                              reason: "Переполнение начального адреса")
        }
        let (end, endOverflow) = start.addingReportingOverflow(requiredBytes)
        guard !endOverflow else {
            return Assessment(verdict: .invalidInput, startBytes: start,
                              endExclusiveBytes: nil,
                              reason: "Переполнение конечного адреса")
        }
        guard let partitionEnd = partition.endExclusiveBytes else {
            return Assessment(verdict: .invalidInput, startBytes: start,
                              endExclusiveBytes: end,
                              reason: "Некорректная геометрия раздела")
        }
        guard start >= partition.offsetBytes, end <= partitionEnd else {
            return Assessment(verdict: .outsidePartition, startBytes: start,
                              endExclusiveBytes: end,
                              reason: "Запрошенный диапазон RAW emuMMC выходит за пределы раздела")
        }
        return Assessment(verdict: .fitsWithinPartition, startBytes: start,
                          endExclusiveBytes: end,
                          reason: "Заданный диапазон помещается в раздел; структура NAND не проверена")
    }
}
