import Foundation

/// Read-only, metadata-only manifest for a mounted source directory.
/// Does not copy data or calculate content checksums. This is NOT a snapshot.
public enum SakuraMigrationManifest {
    public enum Kind: String, Sendable, Equatable {
        case file
        case directory
    }

    public struct Entry: Sendable, Equatable {
        public let relativePath: String
        public let kind: Kind
        /// Logical size for regular files; nil for directories.
        public let logicalBytes: UInt64?
    }

    public struct Report: Sendable, Equatable {
        /// The root itself is not an entry; empty directories below the root are.
        public let entries: [Entry]
        public let totalLogicalBytes: UInt64?
        public let errors: [String]
        public let skippedPaths: [String]
        public var complete: Bool { errors.isEmpty && totalLogicalBytes != nil }
        public var fileCount: Int { entries.filter { $0.kind == .file }.count }
        public var directoryCount: Int { entries.filter { $0.kind == .directory }.count }
    }

    public static func inspect(
        root: URL,
        policy: SakuraMigrationInventory.Policy = .strict
    ) -> Report {
        let fm = FileManager.default
        let rootURL = root.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .fileSizeKey, .isReadableKey
        ]
        var entries: [Entry] = []
        var skipped: [String] = []
        var errors: [String] = []
        var total: UInt64 = 0

        func shouldSkip(_ name: String, topLevel: Bool) -> Bool {
            guard case .excludeKnownMacOSMetadata = policy else { return false }
            if name.hasPrefix("._") || name == ".DS_Store" { return true }
            return topLevel && [".Spotlight-V100", ".Trashes", ".fseventsd"].contains(name)
        }

        // Reject symlink roots; do not resolve destination paths.
        do {
            let rootValues = try rootURL.resourceValues(forKeys: keys)
            guard rootValues.isSymbolicLink != true && rootValues.isDirectory == true else {
                return Report(entries: [], totalLogicalBytes: nil,
                              errors: ["Корневой путь не является обычным каталогом"], skippedPaths: [])
            }
        } catch {
            return Report(entries: [], totalLogicalBytes: nil,
                          errors: ["Не удалось проверить корень: \(error.localizedDescription)"], skippedPaths: [])
        }

        func walk(_ directory: URL, relative: String, topLevel: Bool) {
            let children: [URL]
            do {
                children = try fm.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: [])
            } catch {
                errors.append("Не удалось прочитать каталог \(directory.path): \(error.localizedDescription)")
                return
            }
            for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = child.lastPathComponent
                // Defensive check: never assemble paths containing traversal components.
                guard !name.isEmpty && name != "." && name != ".." && !name.contains("/") else {
                    errors.append("Некорректное имя объекта в каталоге: \(directory.path)")
                    continue
                }
                let path = relative.isEmpty ? name : relative + "/" + name
                if shouldSkip(name, topLevel: topLevel) {
                    skipped.append(path)
                    continue
                }
                do {
                    let values = try child.resourceValues(forKeys: keys)
                    if values.isSymbolicLink == true {
                        errors.append("Символическая ссылка требует ручной проверки: \(path)")
                    } else if values.isDirectory == true {
                        entries.append(Entry(relativePath: path, kind: .directory, logicalBytes: nil))
                        walk(child, relative: path, topLevel: false)
                    } else if values.isRegularFile == true {
                        guard values.isReadable == true, let size = values.fileSize, size >= 0 else {
                            errors.append("Неизвестен размер или доступность файла: \(path)")
                            continue
                        }
                        let (next, overflow) = total.addingReportingOverflow(UInt64(size))
                        if overflow {
                            errors.append("Переполнение суммарного размера: \(path)")
                            continue
                        }
                        total = next
                        entries.append(Entry(relativePath: path, kind: .file, logicalBytes: UInt64(size)))
                    } else {
                        errors.append("Неподдерживаемый тип объекта: \(path)")
                    }
                } catch {
                    errors.append("Ошибка чтения метаданных \(path): \(error.localizedDescription)")
                }
            }
        }
        walk(rootURL, relative: "", topLevel: true)
        return Report(entries: entries.sorted { $0.relativePath < $1.relativePath },
                      totalLogicalBytes: errors.isEmpty ? total : nil,
                      errors: errors, skippedPaths: skipped.sorted())
    }
}
