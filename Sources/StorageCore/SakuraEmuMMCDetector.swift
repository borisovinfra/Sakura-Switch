import Foundation

/// Reads Hekate's emuMMC configuration without accessing NAND or modifying the SD card.
public enum SakuraEmuMMCDetector {
    public enum Mode: String, Sendable, Equatable {
        case fileBased
        case partitionBased
        case disabled
        case unknown
    }

    public struct Result: Sendable, Equatable {
        public let mode: Mode
        public let path: String?
        public let sector: UInt64?
        public let enabled: Bool?
        public let warnings: [String]

        public init(mode: Mode, path: String?, sector: UInt64?, enabled: Bool?, warnings: [String]) {
            self.mode = mode
            self.path = path
            self.sector = sector
            self.enabled = enabled
            self.warnings = warnings
        }
    }

    public static func inspect(fileAt url: URL) throws -> Result {
        let contents = try String(contentsOf: url, encoding: .utf8)
        return inspect(text: contents)
    }

    /// Parses only the [emummc] section. 'partitionBased' is a configuration
    /// indication, not proof that a valid emuMMC partition exists.
    public static func inspect(text: String) -> Result {
        var values: [String: String] = [:]
        var inSection = false
        var foundSection = false
        var warnings: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                let section = line.dropFirst().dropLast().trimmingCharacters(in: .whitespacesAndNewlines)
                inSection = section.lowercased() == "emummc"
                if inSection { foundSection = true }
                continue
            }
            guard inSection, let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if values[key] != nil { warnings.append("Повтор параметра: \(key)") }
            values[key] = value
        }

        guard foundSection else {
            return Result(mode: .unknown, path: nil, sector: nil, enabled: nil,
                          warnings: ["Секция [emummc] не найдена"])
        }

        let enabled: Bool?
        switch values["enabled"] {
        case "1": enabled = true
        case "0": enabled = false
        default:
            enabled = nil
            warnings.append("Параметр enabled отсутствует или некорректен")
        }
        let path = values["path"].flatMap { $0.isEmpty ? nil : $0 }
        var sector: UInt64?
        if let raw = values["sector"] {
            let lower = raw.lowercased()
            if lower.hasPrefix("0x") {
                sector = UInt64(lower.dropFirst(2), radix: 16)
            } else {
                sector = UInt64(lower, radix: 16)
            }
            if sector == nil { warnings.append("Некорректное значение sector") }
        }

        if enabled == false {
            return Result(mode: .disabled, path: path, sector: sector, enabled: enabled, warnings: warnings)
        }
        guard enabled == true else {
            return Result(mode: .unknown, path: path, sector: sector, enabled: enabled, warnings: warnings)
        }
        if let sector, sector > 0 {
            return Result(mode: .partitionBased, path: path, sector: sector, enabled: enabled, warnings: warnings)
        }
        if values["sector"] != nil && sector == nil {
            return Result(mode: .unknown, path: path, sector: nil, enabled: enabled, warnings: warnings)
        }
        if let path, !path.isEmpty {
            return Result(mode: .fileBased, path: path, sector: sector, enabled: enabled,
                          warnings: warnings + ["Файловый режим предполагается по конфигурации; файлы NAND ещё не проверены"])
        }
        return Result(mode: .unknown, path: path, sector: sector, enabled: enabled,
                      warnings: warnings + ["Не указаны достаточные параметры размещения emuMMC"])
    }
}
