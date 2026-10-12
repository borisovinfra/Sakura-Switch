import Foundation
import Darwin

/// Experimental, synchronous, fail-closed batch wrapper around SakuraVerifiedCopy.
/// No automatic mkdir, overwrite, rollback, resume or disk selection.
/// Destination directory tree must already exist and be explicitly prepared.
public enum SakuraVerifiedTransfer {
    public enum Failure: Error, LocalizedError {
        case incompleteManifest, excludedEntries, invalidEntry(String), unsupportedSize(String)
        case unsafeRoots, missingDirectory(String), conflictingEntry(String)
        case stopped, sourceChanged(String)

        public var errorDescription: String? { String(describing: self) }
    }

    public struct Progress: Sendable {
        public let completedFiles: Int
        public let totalFiles: Int
        public let completedBytes: UInt64
        public let totalBytes: UInt64
        public let currentPath: String?
    }

    public struct VerifiedFile: Sendable {
        public let relativePath: String
        public let receipt: SakuraVerifiedCopy.Receipt
    }

    public struct Report: Sendable {
        public let verified: [VerifiedFile]
        public let totalBytes: UInt64
    }

    /// Calls `onProgress` between files, never while a file is being written.
    /// An error leaves already published, individually verified files in place.
    /// Caller must inspect them manually; no automatic retry or deletion occurs.
    public static func copy(
        manifest: SakuraMigrationManifest.Report,
        sourceRoot: URL,
        destinationRoot: URL,
        shouldStop: () -> Bool = { false },
        onProgress: (Progress) -> Void = { _ in }
    ) throws -> Report {
        guard manifest.complete, let total = manifest.totalLogicalBytes else {
            throw Failure.incompleteManifest
        }
        guard manifest.skippedPaths.isEmpty else { throw Failure.excludedEntries }
        let source = sourceRoot.standardizedFileURL
        let target = destinationRoot.standardizedFileURL
        try checkDirectory(source)
        try checkDirectory(target)
        let srcPath = source.path, dstPath = target.path
        guard srcPath != dstPath,
              !dstPath.hasPrefix(srcPath + "/"),
              !srcPath.hasPrefix(dstPath + "/") else { throw Failure.unsafeRoots }

        // Validate every path and the complete size BEFORE copying the first file.
        var seen = Set<String>()
        var files: [SakuraMigrationManifest.Entry] = []
        var sum: UInt64 = 0
        for entry in manifest.entries {
            let path = entry.relativePath
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty, parts.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("\\") && !$0.hasPrefix("._")
            }) else { throw Failure.invalidEntry(path) }
            let folded = path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(folded).inserted else { throw Failure.conflictingEntry(path) }
            if entry.kind == .file {
                guard let size = entry.logicalBytes else { throw Failure.invalidEntry(path) }
                guard size <= 4_294_967_295 else { throw Failure.unsupportedSize(path) }
                let (next, overflow) = sum.addingReportingOverflow(size)
                guard !overflow else { throw Failure.invalidEntry(path) }
                sum = next
                files.append(entry)
            } else if entry.logicalBytes != nil {
                throw Failure.invalidEntry(path)
            }
        }
        guard sum == total else { throw Failure.incompleteManifest }
        // A file cannot be an ancestor of another manifest entry.
        let filePaths = Set(files.map(\.relativePath))
        for entry in manifest.entries {
            let parts = entry.relativePath.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for n in 1..<parts.count {
                    let ancestor = parts.prefix(n).joined(separator: "/")
                    if filePaths.contains(ancestor) { throw Failure.conflictingEntry(ancestor) }
                }
            }
        }

        // Directory layout must already exist. No filesystem mutation in preflight.
        for entry in manifest.entries where entry.kind == .directory {
            try checkDirectory(target.appendingPathComponent(entry.relativePath, isDirectory: true))
        }
        for entry in files {
            let relative = entry.relativePath
            let parent = (relative as NSString).deletingLastPathComponent
            let destDir = parent.isEmpty ? target : target.appendingPathComponent(parent, isDirectory: true)
            try checkDirectory(destDir)
            let destFile = destDir.appendingPathComponent((relative as NSString).lastPathComponent)
            var existing = stat()
            // lstat includes dangling links; refuse any existing object.
            guard lstat(destFile.path, &existing) != 0, errno == ENOENT else {
                throw Failure.conflictingEntry(relative)
            }
        }

        var receipts: [VerifiedFile] = []
        var completedBytes: UInt64 = 0
        let ordered = files.sorted { $0.relativePath < $1.relativePath }
        onProgress(Progress(completedFiles: 0, totalFiles: ordered.count,
                            completedBytes: 0, totalBytes: total, currentPath: nil))
        for entry in ordered {
            if shouldStop() { throw Failure.stopped }
            let path = entry.relativePath
            let parent = (path as NSString).deletingLastPathComponent
            let destDir = parent.isEmpty ? target : target.appendingPathComponent(parent, isDirectory: true)
            let name = (path as NSString).lastPathComponent
            let receipt = try SakuraVerifiedCopy.copy(
                source: source.appendingPathComponent(path), toDirectory: destDir, name: name)
            guard receipt.bytes == entry.logicalBytes else { throw Failure.sourceChanged(path) }
            let (next, overflow) = completedBytes.addingReportingOverflow(receipt.bytes)
            guard !overflow else { throw Failure.incompleteManifest }
            completedBytes = next
            receipts.append(VerifiedFile(relativePath: path, receipt: receipt))
            onProgress(Progress(completedFiles: receipts.count, totalFiles: ordered.count,
                                completedBytes: completedBytes, totalBytes: total, currentPath: path))
        }
        return Report(verified: receipts, totalBytes: completedBytes)
    }

    private static func checkDirectory(_ url: URL) throws {
        let path = url.standardizedFileURL.path
        var current = ""
        for piece in URL(fileURLWithPath: path).pathComponents {
            if piece == "/" { current = "/"; continue }
            current = (current == "/" ? "/" : current + "/") + piece
            var st = stat()
            guard lstat(current, &st) == 0,
                  (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw Failure.unsafeRoots
            }
        }
    }
}
