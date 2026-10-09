import Foundation

/// Read-only structural inspection of Hekate file-based eMMC files.
/// Never reads NAND contents and cannot establish integrity or bootability.
public enum SakuraNANDStructureValidator {
    public struct Entry: Sendable, Equatable {
        public let name: String
        public let sizeBytes: UInt64
        public let isRegularFile: Bool
        public init(name: String, sizeBytes: UInt64, isRegularFile: Bool) {
            self.name = name
            self.sizeBytes = sizeBytes
            self.isRegularFile = isRegularFile
        }
    }

    public enum Status: String, Sendable, Equatable {
        case consistentMetadata
        case incomplete
        case unknown
    }

    public struct Report: Sendable, Equatable {
        public let status: Status
        public let chunkCount: Int
        public let gppBytes: UInt64?
        public let totalBytes: UInt64?
        public let messages: [String]
    }

    private static func report(_ status: Status, _ chunks: Int, _ gpp: UInt64?,
                               _ total: UInt64?, _ message: String) -> Report {
        Report(status: status, chunkCount: chunks, gppBytes: gpp,
               totalBytes: total, messages: [message])
    }

    /// Pure metadata check. Equal non-final chunks are expected; the last may be smaller.
    /// A plausible sequence is NOT proof that its final chunk is complete.
    public static func assess(entries: [Entry]) -> Report {
        let byName = Dictionary(grouping: entries, by: \.name)
        guard byName.values.allSatisfy({ $0.count == 1 }) else {
            return report(.incomplete, 0, nil, nil, "Обнаружены повторяющиеся имена файлов")
        }
        guard let boot0 = byName["BOOT0"]?.first,
              let boot1 = byName["BOOT1"]?.first,
              boot0.isRegularFile, boot1.isRegularFile,
              boot0.sizeBytes > 0, boot1.sizeBytes > 0 else {
            return report(.incomplete, 0, nil, nil, "BOOT0 или BOOT1 отсутствует, пуст либо не является обычным файлом")
        }
        guard boot0.sizeBytes == 4 * 1024 * 1024,
              boot1.sizeBytes == 4 * 1024 * 1024 else {
            return report(.incomplete, 0, nil, nil, "Размер BOOT0/BOOT1 отличается от ожидаемых 4 МиБ")
        }
        let numeric = entries.filter { !$0.name.isEmpty && $0.name.allSatisfy(\.isNumber) }
        guard !numeric.isEmpty else {
            return report(.incomplete, 0, nil, nil, "Не найдены фрагменты GPP")
        }
        var indexes: [Int: Entry] = [:]
        for item in numeric {
            guard item.name.count == 2,
                  item.name.unicodeScalars.allSatisfy({ $0.value >= 48 && $0.value <= 57 }),
                  let index = Int(item.name), index < 100,
                  indexes[index] == nil, item.isRegularFile, item.sizeBytes > 0 else {
                return report(.incomplete, numeric.count, nil, nil, "Некорректное имя, тип или размер фрагмента GPP")
            }
            indexes[index] = item
        }
        guard let largest = indexes.keys.max(), largest + 1 == indexes.count else {
            return report(.incomplete, numeric.count, nil, nil, "Пропуск в последовательности фрагментов GPP")
        }
        guard let firstSize = indexes[0]?.sizeBytes else {
            return report(.incomplete, numeric.count, nil, nil, "Отсутствует начальный фрагмент 00")
        }
        var sum: UInt64 = 0
        for index in 0...largest {
            guard let size = indexes[index]?.sizeBytes,
                  (index == largest ? size <= firstSize : size == firstSize) else {
                return report(.incomplete, numeric.count, nil, nil, "Размеры фрагментов GPP непоследовательны")
            }
            let (next, overflow) = sum.addingReportingOverflow(size)
            guard !overflow else {
                return report(.unknown, numeric.count, nil, nil, "Переполнение суммарного размера GPP")
            }
            sum = next
        }
        let (total, overflow) = sum.addingReportingOverflow(boot0.sizeBytes + boot1.sizeBytes)
        guard !overflow else {
            return report(.unknown, numeric.count, sum, nil, "Переполнение общего размера NAND")
        }
        return report(.consistentMetadata, numeric.count, sum, total,
                      "Последовательность и размеры выглядят согласованно. Полнота последнего фрагмента и целостность NAND не подтверждены")
    }

    /// Examine only directory entries and filesystem metadata. Symlinks are rejected.
    public static func inspect(eMMCDirectory: URL) -> Report {
        let fm = FileManager.default
        do {
            let urls = try fm.contentsOfDirectory(at: eMMCDirectory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [])
            var entries: [Entry] = []
            for url in urls {
                let values = try url.resourceValues(forKeys:
                    [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                let regular = values.isRegularFile == true && values.isSymbolicLink != true
                let size = values.fileSize.flatMap { $0 >= 0 ? UInt64($0) : nil } ?? 0
                entries.append(Entry(name: url.lastPathComponent,
                                     sizeBytes: size, isRegularFile: regular))
            }
            return assess(entries: entries)
        } catch {
            return report(.unknown, 0, nil, nil,
                          "Не удалось прочитать метаданные eMMC: \(error.localizedDescription)")
        }
    }
}
