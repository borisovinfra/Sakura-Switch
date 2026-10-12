import Foundation

/// Arithmetic-only Hekate RAW emuMMC layout check. No disk access.
/// Source: Hekate bootloader/storage/emummc.c, emummc_raw_get_part_off().
public enum SakuraRAWLayoutValidator {
    public static let bootSectors: UInt64 = 0x2000 // 4 MiB each at 512 B/sector
    public static let gppOffsetSectors: UInt64 = 0x4000

    public enum Verdict: String, Sendable, Equatable {
        case fitsWithinPartition
        case outsidePartition
        case invalidInput
    }

    public struct Assessment: Sendable, Equatable {
        public let verdict: Verdict
        public let boot0StartBytes: UInt64?
        public let boot1StartBytes: UInt64?
        public let gppStartBytes: UInt64?
        public let endExclusiveBytes: UInt64?
        public let reason: String
    }

    /// `gppSectors` MUST be established independently from the original NAND.
    /// `sector` is the Hekate base sector (512-byte units), not a macOS block index.
    public static func assess(
        sector: UInt64?,
        gppSectors: UInt64,
        partition: StoragePartitionGeometry
    ) -> Assessment {
        func invalid(_ reason: String) -> Assessment {
            Assessment(verdict: .invalidInput, boot0StartBytes: nil,
                       boot1StartBytes: nil, gppStartBytes: nil,
                       endExclusiveBytes: nil, reason: reason)
        }
        guard let sector, sector > 0, gppSectors > 0 else {
            return invalid("Не задан базовый сектор или подтверждённый размер GPP")
        }
        // Hekate's emu_cfg.sector and storage sector addresses are uint32_t.
        guard sector <= UInt64(UInt32.max) else {
            return invalid("Адрес сектора не представим в 32-битной адресации Hekate")
        }
        let (gppStartSector, sumOverflow) = sector.addingReportingOverflow(gppOffsetSectors)
        guard !sumOverflow else { return invalid("Переполнение смещения GPP") }
        let (lastSectorExclusive, endOverflow) = gppStartSector.addingReportingOverflow(gppSectors)
        guard !endOverflow, lastSectorExclusive <= UInt64(UInt32.max) + 1 else {
            return invalid("Размер GPP превышает 32-битную адресацию секторов")
        }
        let (boot1Sector, bootOverflow) = sector.addingReportingOverflow(bootSectors)
        guard !bootOverflow else { return invalid("Переполнение смещения BOOT1") }
        let bytes = SakuraRAWValidator.sectorSizeBytes
        let (boot0, o0) = sector.multipliedReportingOverflow(by: bytes)
        let (boot1, o1) = boot1Sector.multipliedReportingOverflow(by: bytes)
        let (gpp, o2) = gppStartSector.multipliedReportingOverflow(by: bytes)
        let (end, o3) = lastSectorExclusive.multipliedReportingOverflow(by: bytes)
        guard !o0 && !o1 && !o2 && !o3 else { return invalid("Переполнение байтового адреса") }
        guard let partitionEnd = partition.endExclusiveBytes else { return invalid("Некорректная геометрия раздела") }
        let fits = boot0 >= partition.offsetBytes && end <= partitionEnd
        return Assessment(
            verdict: fits ? .fitsWithinPartition : .outsidePartition,
            boot0StartBytes: boot0, boot1StartBytes: boot1,
            gppStartBytes: gpp, endExclusiveBytes: end,
            reason: fits
                ? "Все рассчитанные области помещаются; содержимое NAND не проверено"
                : "Диапазон BOOT0/BOOT1/GPP выходит за границы раздела"
        )
    }
}
