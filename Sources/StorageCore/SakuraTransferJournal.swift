import Foundation
import CryptoKit
import Darwin

/// Immutable checkpoints of completed, SHA-256-verified file transfers.
/// A checkpoint alone never authorizes skipping or overwriting files.
/// Initial version: records only *completed* transfers, not interrupted runs.
public enum SakuraTransferJournal {
    public enum Failure: Error {
        case invalidPath, invalidRecord, unsafeDirectory, alreadyExists, invalidJSON
        case missingFile(String), changedFile(String), io(Int32)
    }

    public struct Entry: Codable, Sendable, Equatable {
        public let relativePath: String
        public let bytes: UInt64
        public let sha256: String
    }

    public struct Checkpoint: Codable, Sendable, Equatable {
        public let formatVersion: Int
        public let files: [Entry]
    }

    /// Build a checkpoint from a transfer that has returned successfully.
    public static func make(from report: SakuraVerifiedTransfer.Report) throws -> Checkpoint {
        var seen = Set<String>()
        var entries: [Entry] = []
        for item in report.verified {
            let path = item.relativePath
            guard validRelativePath(path), validDigest(item.receipt.sha256) else { throw Failure.invalidRecord }
            let folded = path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(folded).inserted else { throw Failure.invalidRecord }
            entries.append(Entry(relativePath: path, bytes: item.receipt.bytes, sha256: item.receipt.sha256))
        }
        return Checkpoint(formatVersion: 1, files: entries.sorted { $0.relativePath < $1.relativePath })
    }

    /// Create a NEW immutable JSON checkpoint. Never replace an existing path.
    /// A temporary file is synced and published using macOS exclusive rename.
    public static func save(_ checkpoint: Checkpoint, toDirectory directory: URL, name: String) throws {
        try validate(checkpoint)
        guard validName(name), name.hasSuffix(".json") else { throw Failure.invalidPath }
        let dir = directory.standardizedFileURL
        try checkPath(dir, directory: true)
        let final = dir.appendingPathComponent(name)
        let tmp = dir.appendingPathComponent(".sakura-journal-\(UUID().uuidString).tmp")
        let bytes = try JSONEncoder().encode(checkpoint)
        let fd = open(tmp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { throw Failure.io(errno) }
        var openFD = true
        defer { if openFD { _ = close(fd) }; _ = unlink(tmp.path) }
        try bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let n = write(fd, base.advanced(by: offset), raw.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.io(errno) }
                offset += n
            }
        }
        guard fsync(fd) == 0 else { throw Failure.io(errno) }
        guard close(fd) == 0 else { openFD = false; throw Failure.io(errno) }
        openFD = false
        guard renameatx_np(AT_FDCWD, tmp.path, AT_FDCWD, final.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw Failure.alreadyExists }
            throw Failure.io(errno)
        }
    }

    public static func load(from url: URL) throws -> Checkpoint {
        let src = url.standardizedFileURL
        try checkPath(src, directory: false)
        let data = try Data(contentsOf: src)
        guard let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data) else { throw Failure.invalidJSON }
        try validate(checkpoint)
        return checkpoint
    }

    /// Independently read every destination file and recompute SHA-256.
    /// Does not resume transfers or trust the checkpoint as proof by itself.
    public static func verify(_ checkpoint: Checkpoint, at destinationRoot: URL) throws -> Int {
        try validate(checkpoint)
        let root = destinationRoot.standardizedFileURL
        try checkPath(root, directory: true)
        var verified = 0
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }
        for entry in checkpoint.files {
            let path = root.appendingPathComponent(entry.relativePath)
            do { try checkPath(path, directory: false) }
            catch { throw Failure.missingFile(entry.relativePath) }
            let fd = open(path.path, O_RDONLY | O_NOFOLLOW)
            guard fd >= 0 else { throw Failure.missingFile(entry.relativePath) }
            defer { _ = close(fd) }
            var metadata = stat()
            guard fstat(fd, &metadata) == 0,
                  (metadata.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
                  metadata.st_size >= 0,
                  UInt64(metadata.st_size) == entry.bytes else {
                throw Failure.changedFile(entry.relativePath)
            }
            var digest = SHA256()
            var length: UInt64 = 0
            while true {
                let n = read(fd, buffer, bufferSize)
                if n < 0 && errno == EINTR { continue }
                guard n >= 0 else { throw Failure.io(errno) }
                if n == 0 { break }
                digest.update(data: Data(bytes: buffer, count: n))
                length += UInt64(n)
            }
            let actual = Data(digest.finalize()).map { String(format: "%02x", $0) }.joined()
            guard length == entry.bytes && actual == entry.sha256 else { throw Failure.changedFile(entry.relativePath) }
            verified += 1
        }
        return verified
    }

    private static func validate(_ checkpoint: Checkpoint) throws {
        guard checkpoint.formatVersion == 1 else { throw Failure.invalidRecord }
        var seen = Set<String>()
        for item in checkpoint.files {
            guard validRelativePath(item.relativePath), validDigest(item.sha256) else { throw Failure.invalidRecord }
            let folded = item.relativePath.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard seen.insert(folded).inserted else { throw Failure.invalidRecord }
        }
    }

    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\\") && !name.hasPrefix("._")
    }
    private static func validRelativePath(_ path: String) -> Bool {
        !path.isEmpty && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { validName(String($0)) }
    }
    private static func validDigest(_ digest: String) -> Bool {
        digest.utf8.count == 64 && digest.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private static func checkPath(_ url: URL, directory: Bool) throws {
        var cursor = ""
        let parts = url.standardizedFileURL.pathComponents
        for (index, piece) in parts.enumerated() {
            if piece == "/" { cursor = "/"; continue }
            cursor = (cursor == "/" ? "/" : cursor + "/") + piece
            var st = stat()
            guard lstat(cursor, &st) == 0 else { throw Failure.invalidPath }
            let wantDir = index < parts.count - 1 || directory
            guard (st.st_mode & mode_t(S_IFMT)) == (wantDir ? mode_t(S_IFDIR) : mode_t(S_IFREG)) else {
                throw Failure.unsafeDirectory
            }
        }
    }
}
