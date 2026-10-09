import Foundation
import CryptoKit
import Darwin

/// Experimental single-file copier for controlled test directories.
/// No resume, no disk discovery, no permission to overwrite existing files.
public enum SakuraVerifiedCopy {
    public enum Failure: Error, LocalizedError {
        case invalidPath, unsafeSource, unsafeDestination, alreadyExists, sizeChanged, checksumMismatch, io(String)
        public var errorDescription: String? { String(describing: self) }
    }

    public struct Receipt: Sendable {
        public let bytes: UInt64
        public let sha256: String
    }

    /// Copies one regular file into an existing, explicitly selected directory.
    /// File names must be a single component. Destination directories are never created.
    /// A uniquely named temporary file is used; publishing uses exclusive rename (no overwrite).
    public static func copy(source: URL, toDirectory destinationDirectory: URL, name: String) throws -> Receipt {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
              !name.hasPrefix("._") else { throw Failure.invalidPath }
        let src = source.standardizedFileURL
        let dir = destinationDirectory.standardizedFileURL
        guard src.path != dir.path, !dir.path.hasPrefix(src.path + "/") else { throw Failure.invalidPath }

        // Reject links, nonregular files and symlinked ancestor paths (fail closed).
        try rejectLinksInPath(src, expectDirectory: false)
        try rejectLinksInPath(dir, expectDirectory: true)
        let final = dir.appendingPathComponent(name)
        guard final.path != src.path else { throw Failure.invalidPath }
        guard !FileManager.default.fileExists(atPath: final.path),
              !isLink(final.path) else { throw Failure.alreadyExists }

        let srcFD = open(src.path, O_RDONLY | O_NOFOLLOW)
        guard srcFD >= 0 else { throw Failure.unsafeSource }
        defer { close(srcFD) }
        var before = stat()
        guard fstat(srcFD, &before) == 0, (before.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG), before.st_size >= 0 else {
            throw Failure.unsafeSource
        }

        // Pin the verified destination directory for all destination operations.
        let dirFD = open(dir.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard dirFD >= 0 else { throw Failure.unsafeDestination }
        defer { close(dirFD) }
        var dirInfo = stat()
        guard fstat(dirFD, &dirInfo) == 0,
              (dirInfo.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw Failure.unsafeDestination
        }
        let tempName = ".sakura-partial-\(UUID().uuidString)"
        let dstFD = openat(dirFD, tempName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        guard dstFD >= 0 else { throw Failure.unsafeDestination }
        var dstOpen = true
        defer {
            if dstOpen { close(dstFD) }
            _ = unlinkat(dirFD, tempName, 0)
        }
        var srcHash = SHA256()
        var transferred: UInt64 = 0
        let bufferSize = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 1)
        defer { buffer.deallocate() }
        while true {
            let count = read(srcFD, buffer, bufferSize)
            if count < 0 { if errno == EINTR { continue }; throw Failure.io("read failed") }
            if count == 0 { break }
            let chunk = Data(bytes: buffer, count: count)
            srcHash.update(data: chunk)
            var offset = 0
            while offset < count {
                let n = write(dstFD, buffer.advanced(by: offset), count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Failure.io("write failed") }
                offset += n
            }
            transferred += UInt64(count)
        }
        var after = stat()
        guard fstat(srcFD, &after) == 0, transferred == UInt64(before.st_size),
              before.st_size == after.st_size, before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw Failure.sizeChanged }
        guard fsync(dstFD) == 0 else { throw Failure.io("sync failed") }
        close(dstFD)
        dstOpen = false

        let expected = Data(srcHash.finalize())
        let verifyFD = openat(dirFD, tempName, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard verifyFD >= 0 else { throw Failure.io("verification open failed") }
        defer { close(verifyFD) }
        var destHash = SHA256()
        while true {
            let count = read(verifyFD, buffer, bufferSize)
            if count < 0 { if errno == EINTR { continue }; throw Failure.io("verification read failed") }
            if count == 0 { break }
            destHash.update(data: Data(bytes: buffer, count: count))
        }
        guard Data(destHash.finalize()) == expected else { throw Failure.checksumMismatch }
        // FAT32 has no hard links. macOS RENAME_EXCL publishes without replacing
        // an existing destination; regular rename() is unsafe here.
        guard renameatx_np(dirFD, tempName, dirFD, name,
                           UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST { throw Failure.alreadyExists }
            throw Failure.io("exclusive publish failed (errno \(code))")
        }
        return Receipt(bytes: transferred, sha256: expected.map { String(format: "%02x", $0) }.joined())
    }

    private static func isLink(_ path: String) -> Bool {
        var s = stat()
        return lstat(path, &s) == 0 && (s.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK)
    }

    private static func rejectLinksInPath(_ url: URL, expectDirectory: Bool) throws {
        let parts = url.pathComponents
        var p = ""
        for part in parts {
            if part == "/" { p = "/"; continue }
            p = (p == "/" ? "/" : p + "/") + part
            var s = stat()
            guard lstat(p, &s) == 0, (s.st_mode & mode_t(S_IFMT)) != mode_t(S_IFLNK) else {
                throw Failure.invalidPath
            }
        }
        var s = stat()
        guard lstat(url.path, &s) == 0,
              (s.st_mode & mode_t(S_IFMT)) == (expectDirectory ? mode_t(S_IFDIR) : mode_t(S_IFREG)) else {
            throw Failure.invalidPath
        }
    }
}
