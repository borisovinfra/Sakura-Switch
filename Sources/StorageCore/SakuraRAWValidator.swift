import Foundation

/// Read-only numerical assessment of a Hekate RAW emuMMC base sector.
/// This does not inspect NAND contents or prove bootability.
public enum SakuraRAWValidator {
    /// Hekate SD-sector addressing uses 512-byte sectors; this is independent
    /// of the block size reported for a macOS partition device.
    public static let sectorSizeBytes: UInt64 = 512

    public enum Verdict: String, Sendable, Equatable {
        case candidateWithinPartition
        case outsidePartition
        case invalidInput
    }

    public struct Assessment: Sendable, Equatable {
        public let verdict: Verdict
        public let baseOffsetBytes: UInt64?
        public let reason: String
    }

    /// Check only whether the configured base sector lies inside the given
    /// partition. The actual RAW emuMMC layout and required space are NOT
    /// validated by this check.
    public static func assess(
        sector: UInt64?,
        partition: StoragePartitionGeometry
    ) -> Assessment {
        guard let sector, sector > 0 else {
            return Assessment(verdict: .invalidInput, baseOffsetBytes: nil,
                              reason: "Отсутствует или равен нулю сектор RAW emuMMC")
        }
        let (base, overflow) = sector.multipliedReportingOverflow(by: sectorSizeBytes)
        guard !overflow else {
            return Assessment(verdict: .invalidInput, baseOffsetBytes: nil,
                              reason: "Переполнение при переводе секторов в байты")
        }
        guard let end = partition.endExclusiveBytes else {
            return Assessment(verdict: .invalidInput, baseOffsetBytes: base,
                              reason: "Некорректная геометрия раздела")
        }
        guard base >= partition.offsetBytes && base < end else {
            return Assessment(verdict: .outsidePartition, baseOffsetBytes: base,
                              reason: "Базовый сектор не находится внутри указанного раздела")
        }
        return Assessment(verdict: .candidateWithinPartition, baseOffsetBytes: base,
                          reason: "Адрес находится внутри раздела; структуру и размер RAW emuMMC ещё нужно проверить")
    }
}
