import Foundation

/// Read-only inventory. Optional exclusions must be explicitly selected by the caller.
/// No file contents are read, copied, or modified.
public enum SakuraMigrationInventory {
    public enum Policy: Sendable {
        case strict
        case excludeKnownMacOSMetadata
    }

    public struct Report: Sendable, Equatable {
        public let fileCount: UInt64
        public let directoryCount: UInt64
        public let totalLogicalBytes: UInt64?
        public let errors: [String]
        /// Relative paths deliberately omitted from the inventory, including whole directories.
        public let skippedPaths: [String]
        /// Complete for the SELECTED inventory policy, not a proof of copy readiness.
        public var complete: Bool { errors.isEmpty && totalLogicalBytes != nil }
    }

    public static func inspect(root: URL, policy: Policy = .strict) -> Report {
        var files: UInt64 = 0
        var directories: UInt64 = 0
        var bytes: UInt64 = 0
        var errors: [String] = []
        var skipped: [String] = []
        let fm = FileManager.default
        let path = root.standardizedFileURL
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .fileSizeKey, .isReadableKey
        ]
        func add(_ url: URL) -> Bool {
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    errors.append("Символическая ссылка требует ручной проверки: \(url.path)")
                    return false
                }
                if values.isDirectory == true {
                    let (next, overflow) = directories.addingReportingOverflow(1)
                    if overflow { errors.append("Переполнение числа каталогов"); return false }
                    directories = next
                    return true
                }
                guard values.isRegularFile == true else {
                    errors.append("Неподдерживаемый объект: \(url.path)")
                    return false
                }
                guard values.isReadable == true, let size = values.fileSize, size >= 0 else {
                    errors.append("Не удалось определить размер или доступность: \(url.path)")
                    return false
                }
                let (newFiles, fileOverflow) = files.addingReportingOverflow(1)
                let (newBytes, byteOverflow) = bytes.addingReportingOverflow(UInt64(size))
                guard !fileOverflow && !byteOverflow else {
                    errors.append("Переполнение счётчиков")
                    return false
                }
                files = newFiles
                bytes = newBytes
                return true
            } catch {
                errors.append("Не удалось прочитать метаданные \(url.path): \(error.localizedDescription)")
                return false
            }
        }
        func shouldSkip(_ name: String, topLevel: Bool) -> Bool {
            guard case .excludeKnownMacOSMetadata = policy else { return false }
            if name.hasPrefix("._") || name == ".DS_Store" { return true }
            return topLevel && [".Spotlight-V100", ".Trashes", ".fseventsd"].contains(name)
        }
        // Root must be a real directory. Do not follow root symlinks.
        guard add(path), (try? path.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
            if errors.isEmpty { errors.append("Корневой путь не является каталогом") }
            return Report(fileCount: files, directoryCount: directories,
                          totalLogicalBytes: nil, errors: errors, skippedPaths: skipped)
        }
        func walk(_ directory: URL, relative: String, topLevel: Bool) {
            let entries: [URL]
            do {
                entries = try fm.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: Array(keys), options: [])
            } catch {
                errors.append("Не удалось прочитать \(directory.path): \(error.localizedDescription)")
                return
            }
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = url.lastPathComponent
                let childRelative = relative.isEmpty ? name : relative + "/" + name
                if shouldSkip(name, topLevel: topLevel) {
                    skipped.append(childRelative)
                    continue
                }
                guard add(url) else { continue }
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    walk(url, relative: childRelative, topLevel: false)
                }
            }
        }
        walk(path, relative: "", topLevel: true)
        return Report(fileCount: files, directoryCount: directories,
                      totalLogicalBytes: errors.isEmpty ? bytes : nil,
                      errors: errors, skippedPaths: skipped)
    }
}
