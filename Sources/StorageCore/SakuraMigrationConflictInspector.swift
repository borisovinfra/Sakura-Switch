import Foundation

/// Pure metadata comparison. Never opens a target volume or authorizes copying.
/// Both manifests must be produced for explicitly selected roots and reviewed policies.
public enum SakuraMigrationConflictInspector {
    public enum Status: String, Sendable, Equatable {
        case blocked
        case needsMoreInformation
        case noDetectedConflicts
    }

    public struct Report: Sendable, Equatable {
        public let status: Status
        public let conflicts: [String]
        public let messages: [String]
        /// Only true for complete, validated metadata inputs with no detected conflicts.
        /// Not proof that the target remains unchanged or that copying is safe.
        public var conflictsAbsent: Bool? {
            switch status {
            case .noDetectedConflicts: return true
            case .blocked: return false
            case .needsMoreInformation: return nil
            }
        }
    }

    public static let fat32MaximumFileBytes: UInt64 = 4_294_967_295

    public static func assess(
        source: SakuraMigrationManifest.Report,
        target: SakuraMigrationManifest.Report,
        enforceFAT32FileLimit: Bool = true
    ) -> Report {
        guard source.complete && target.complete else {
            return Report(status: .needsMoreInformation, conflicts: [],
                          messages: ["Неполный манифест источника или назначения: конфликты неизвестны"])
        }
        // Compare only manifests of the selected data sets. Their exclusions are
        // reported to the caller, and must be reviewed separately before migration.
        func key(_ path: String) -> String {
            path.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
        }
        func valid(_ path: String) -> Bool {
            !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") &&
            !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: {
                $0.isEmpty || $0 == "." || $0 == ".."
            })
        }
        func validate(_ report: SakuraMigrationManifest.Report) -> Bool {
            var observed = Set<String>()
            for entry in report.entries {
                guard valid(entry.relativePath),
                      (entry.kind == .file ? entry.logicalBytes != nil : entry.logicalBytes == nil),
                      observed.insert(key(entry.relativePath)).inserted else { return false }
            }
            return true
        }
        guard validate(source) && validate(target) else {
            return Report(status: .blocked, conflicts: [],
                          messages: ["Некорректные, повторяющиеся или неоднозначные пути в манифесте"])
        }
        let targetByKey = Dictionary(uniqueKeysWithValues: target.entries.map { (key($0.relativePath), $0) })
        var problems: [String] = []
        for entry in source.entries {
            if entry.kind == .file, enforceFAT32FileLimit,
               let bytes = entry.logicalBytes, bytes > fat32MaximumFileBytes {
                problems.append("Превышен лимит FAT32: \(entry.relativePath) (\(bytes) байт)")
            }
            let normalized = key(entry.relativePath)
            if let existing = targetByKey[normalized] {
                if entry.kind == .file || existing.kind == .file {
                    problems.append("Путь уже занят на назначении: \(entry.relativePath) [\(existing.kind.rawValue)]")
                }
                // An existing directory is compatible with an incoming directory.
            }
            let components = normalized.split(separator: "/")
            if components.count > 1 {
                for i in 1..<components.count {
                    let parent = components.prefix(i).joined(separator: "/")
                    if targetByKey[parent]?.kind == .file {
                        problems.append("Родительский путь на назначении занят файлом: \(entry.relativePath)")
                        break
                    }
                }
            }
        }
        if !problems.isEmpty {
            return Report(status: .blocked, conflicts: problems.sorted(),
                          messages: ["Обнаружены конфликты путей или ограничения FAT32"])
        }
        return Report(status: .noDetectedConflicts, conflicts: [],
                      messages: ["По двум манифестам конфликтов не обнаружено. Требуются повторная проверка и анализ исключений"])
    }
}
