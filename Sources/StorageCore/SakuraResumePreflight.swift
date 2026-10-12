import Foundation
import CryptoKit
import Darwin

/// Read-only validation for a possible resumed transfer.
/// Does not authorize copying, skipping or deleting files by itself.
public enum SakuraResumePreflight {
    public enum Failure: Error, CustomStringConvertible {
        case incompleteManifest, excludedEntries, invalidPath(String), conflictingEntry(String)
        case checkpointMismatch(String), sourceChanged(String), destinationChanged(String)
        case unjournaledDestination(String), invalidRoots

        public var description: String {
            switch self {
            case .incompleteManifest:
                return "Неполный манифест"
            case .excludedEntries:
                return "Исключения не подтверждены"
            case .invalidPath(let path):
                return "Недопустимый путь: \(path)"
            case .conflictingEntry(let path):
                return "Конфликт файлов: \(path)"
            case .checkpointMismatch(let path):
                return "Несовпадение контрольной точки: \(path)"
            case .sourceChanged(let path):
                return "Изменился исходный файл: \(path)"
            case .destinationChanged(let path):
                return "Изменился файл назначения: \(path)"
            case .unjournaledDestination(let path):
                return "Файл назначения отсутствует в журнале: \(path)"
            case .invalidRoots:
                return "Не удалось подтвердить каталоги источника и назначения"
            }
        }
    }

    public struct Report: Sendable {
        public let verifiedCompletedFiles: Int
        public let remainingFiles: Int
        public let verifiedCompletedBytes: UInt64
    }

    public static func inspect(
        manifest: SakuraMigrationManifest.Report,
        checkpoint: SakuraTransferJournal.Checkpoint,
        sourceRoot: URL,
        destinationRoot: URL,
        approvedSkippedPaths: Set<String> = []
    ) throws -> Report {
        guard manifest.complete else { throw Failure.incompleteManifest }
        guard Set(manifest.skippedPaths) == approvedSkippedPaths else {
            throw Failure.excludedEntries
        }
        guard checkpoint.formatVersion == 1 else { throw Failure.checkpointMismatch("version") }
        let source = sourceRoot.standardizedFileURL
        let destination = destinationRoot.standardizedFileURL
        try requireDirectory(source)
        try requireDirectory(destination)
        guard source.path != destination.path,
              !source.path.hasPrefix(destination.path + "/"),
              !destination.path.hasPrefix(source.path + "/") else { throw Failure.invalidRoots }

        var manifestFiles: [String: UInt64] = [:]
        var manifestPaths = Set<String>()
        var folded = Set<String>()
        var summed: UInt64 = 0
        for entry in manifest.entries {
            let relative = entry.relativePath
            try validateRelative(relative)
            let canonical = relative.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard folded.insert(canonical).inserted else { throw Failure.conflictingEntry(relative) }
            manifestPaths.insert(relative)
            if entry.kind == .file {
                guard let size = entry.logicalBytes, size <= 4_294_967_295 else { throw Failure.incompleteManifest }
                manifestFiles[relative] = size
                let (next, overflow) = summed.addingReportingOverflow(size)
                guard !overflow else { throw Failure.incompleteManifest }
                summed = next
            } else if entry.logicalBytes != nil {
                throw Failure.incompleteManifest
            }
        }
        guard summed == manifest.totalLogicalBytes else { throw Failure.incompleteManifest }
        for path in manifestPaths {
            let parts = path.split(separator: "/")
            for n in 1..<parts.count {
                let ancestor = parts.prefix(n).joined(separator: "/")
                guard manifestFiles[ancestor] == nil else { throw Failure.conflictingEntry(path) }
            }
        }
        for entry in manifest.entries where entry.kind == .directory {
            try requireDirectory(source.appendingPathComponent(entry.relativePath))
            try requireDirectory(destination.appendingPathComponent(entry.relativePath))
        }

        var completed = Set<String>()
        var completedBytes: UInt64 = 0
        for item in checkpoint.files {
            try validateRelative(item.relativePath)
            guard completed.insert(item.relativePath).inserted,
                  let expectedSize = manifestFiles[item.relativePath],
                  expectedSize == item.bytes,
                  item.sha256.utf8.count == 64,
                  item.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            else { throw Failure.checkpointMismatch(item.relativePath) }

            let sourceFile = source.appendingPathComponent(item.relativePath)
            let destFile = destination.appendingPathComponent(item.relativePath)
            guard try hashFile(sourceFile, bytes: item.bytes) == item.sha256 else {
                throw Failure.sourceChanged(item.relativePath)
            }
            guard try hashFile(destFile, bytes: item.bytes) == item.sha256 else {
                throw Failure.destinationChanged(item.relativePath)
            }
            completedBytes += item.bytes
        }
        for (relative, _) in manifestFiles where !completed.contains(relative) {
            let destFile = destination.appendingPathComponent(relative)
            var st = stat()
            guard lstat(destFile.path, &st) == -1, errno == ENOENT else {
                throw Failure.unjournaledDestination(relative)
            }
        }
        return Report(verifiedCompletedFiles: completed.count,
                      remainingFiles: manifestFiles.count - completed.count,
                      verifiedCompletedBytes: completedBytes)
    }

    private static func validateRelative(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.hasPrefix("._")
        }) else { throw Failure.invalidPath(path) }
    }

    private static func requireDirectory(_ url: URL) throws {
        let components = url.standardizedFileURL.pathComponents
        var p = ""
        for component in components {
            if component == "/" { p = "/"; continue }
            p = (p == "/" ? "/" : p + "/") + component
            var st = stat()
            guard lstat(p, &st) == 0, st.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                throw Failure.invalidPath(p)
            }
        }
    }

    private static func hashFile(_ url: URL, bytes: UInt64) throws -> String {
        let parent = url.deletingLastPathComponent()
        try requireDirectory(parent)
        var st = stat()
        guard lstat(url.path, &st) == 0,
              st.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG) else {
            throw Failure.invalidPath(url.path)
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw Failure.invalidPath(url.path) }
        defer { _ = close(fd) }
        var first = stat()
        guard fstat(fd, &first) == 0,
              first.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG),
              first.st_size >= 0,
              UInt64(first.st_size) == bytes else { throw Failure.invalidPath(url.path) }
        var digest = SHA256()
        var count: UInt64 = 0
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256 * 1024, alignment: 1)
        defer { buffer.deallocate() }
        while true {
            let n = read(fd, buffer, 256 * 1024)
            if n < 0 && errno == EINTR { continue }
            guard n >= 0 else { throw Failure.invalidPath(url.path) }
            if n == 0 { break }
            digest.update(data: Data(bytes: buffer, count: n))
            count += UInt64(n)
        }
        var last = stat()
        guard fstat(fd, &last) == 0, count == bytes,
              first.st_size == last.st_size,
              first.st_mtimespec.tv_sec == last.st_mtimespec.tv_sec,
              first.st_mtimespec.tv_nsec == last.st_mtimespec.tv_nsec else {
            throw Failure.invalidPath(url.path)
        }
        return Data(digest.finalize()).map { String(format: "%02x", $0) }.joined()
    }
}
