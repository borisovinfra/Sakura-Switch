import Foundation

/// Read-only structural validation. Does not validate NAND contents or bootability.
public enum SakuraStorageValidator {
    public enum Status: String, Sendable {
        case structurePresent
        case incomplete
        case notApplicable
        case unknown
    }

    public struct Report: Sendable {
        public let status: Status
        public let messages: [String]
        public let inspectedPath: String?
    }

    /// `sdRoot` is the mounted filesystem root of an SD card (or a test fixture).
    /// This function only inspects paths and file metadata.
    public static func inspectFileBased(
        sdRoot: URL,
        configuration: SakuraEmuMMCDetector.Result
    ) -> Report {
        guard configuration.mode == .fileBased else {
            return Report(status: .notApplicable,
                          messages: ["Конфигурация не указывает на файловую emuMMC"],
                          inspectedPath: nil)
        }

        guard let rawPath = configuration.path, !rawPath.isEmpty else {
            return Report(status: .unknown,
                          messages: ["В конфигурации отсутствует путь emuMMC"],
                          inspectedPath: nil)
        }

        // Do not trust arbitrary paths from an INI file. Accept relative paths only.
        let parts = rawPath.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !rawPath.hasPrefix("/"),
              !parts.contains("") && !parts.contains(".") && !parts.contains(".."),
              parts.first?.lowercased() == "emummc" else {
            return Report(status: .unknown,
                          messages: ["Небезопасный или неподдерживаемый путь emuMMC"],
                          inspectedPath: nil)
        }

        let fm = FileManager.default
        let root = sdRoot.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return Report(status: .unknown,
                          messages: ["Корневой каталог карты не найден"],
                          inspectedPath: nil)
        }

        let base = parts.reduce(root) { $0.appendingPathComponent($1, isDirectory: true) }
        let resolved = base.standardizedFileURL.resolvingSymlinksInPath()
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(prefix) else {
            return Report(status: .unknown,
                          messages: ["Путь выходит за пределы выбранной карты"],
                          inspectedPath: nil)
        }
        guard fm.fileExists(atPath: resolved.path, isDirectory: &isDir), isDir.boolValue else {
            return Report(status: .incomplete,
                          messages: ["Каталог файловой emuMMC не найден"],
                          inspectedPath: rawPath)
        }

        // Hekate file-based layouts normally store BOOT0, BOOT1 and numbered
        // NAND chunks in the eMMC subdirectory. Do not assume any fixed size.
        let emmc = resolved.appendingPathComponent("eMMC", isDirectory: true)
        let resolvedEmmc = emmc.resolvingSymlinksInPath()
        guard resolvedEmmc.path.hasPrefix(prefix),
              fm.fileExists(atPath: resolvedEmmc.path, isDirectory: &isDir), isDir.boolValue else {
            return Report(status: .incomplete,
                          messages: ["Каталог eMMC отсутствует или недоступен"],
                          inspectedPath: rawPath)
        }

        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(at: resolvedEmmc,
                                                 includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                 options: [])
        } catch {
            return Report(status: .unknown,
                          messages: ["Не удалось прочитать каталог eMMC: \(error.localizedDescription)"],
                          inspectedPath: rawPath)
        }
        let names = Set(entries.map(\.lastPathComponent))
        var missing: [String] = []
        if !names.contains("BOOT0") { missing.append("BOOT0") }
        if !names.contains("BOOT1") { missing.append("BOOT1") }
        let chunks = entries.filter { url in
            let name = url.lastPathComponent
            return !name.isEmpty && name.allSatisfy(\.isNumber)
        }
        if chunks.isEmpty { missing.append("числовые части NAND") }
        if !missing.isEmpty {
            return Report(status: .incomplete,
                          messages: ["Не найдены: " + missing.joined(separator: ", ")],
                          inspectedPath: rawPath)
        }

        // Presence and nonzero size only. Content, completeness and bootability
        // must be checked separately; never claim the NAND is healthy here.
        for url in entries where url.lastPathComponent == "BOOT0" ||
                                 url.lastPathComponent == "BOOT1" ||
                                 chunks.contains(url) {
            let resolvedFile = url.resolvingSymlinksInPath()
            guard resolvedFile.path.hasPrefix(prefix),
                  let values = try? resolvedFile.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
                return Report(status: .incomplete,
                              messages: ["Файл отсутствует, пуст или недоступен: \(url.lastPathComponent)"],
                              inspectedPath: rawPath)
            }
        }
        return Report(status: .structurePresent,
                      messages: ["Основные файлы обнаружены. Целостность NAND и возможность загрузки не проверены."],
                      inspectedPath: rawPath)
    }
}
