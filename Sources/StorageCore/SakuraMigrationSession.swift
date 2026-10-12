import Foundation
import CryptoKit
import Darwin

/// Immutable description of a file migration session.
/// Does not authorize access to either disk.
public enum SakuraMigrationSession {

    public enum Failure: Error {
        case invalidSession
        case mismatch
    }

    public struct Record: Codable, Sendable, Equatable {
        public let version: Int
        public let sessionID: String
        public let sourceVolumeUUID: String
        public let targetVolumeUUID: String
        public let manifestSHA256: String
        public let approvedSkippedPaths: [String]
    }

    public static func make(
        sessionID: String,
        sourceVolumeUUID: String,
        targetVolumeUUID: String,
        manifest: SakuraMigrationManifest.Report,
        approvedSkippedPaths: Set<String>
    ) throws -> Record {

        guard !sessionID.isEmpty,
              sessionID.utf8.count <= 64,
              sessionID.utf8.allSatisfy({
                  (65...90).contains($0) ||
                  (97...122).contains($0) ||
                  (48...57).contains($0) ||
                  $0 == 45 || $0 == 95
              }),
              !sourceVolumeUUID.isEmpty,
              !targetVolumeUUID.isEmpty,
              sourceVolumeUUID != targetVolumeUUID,
              manifest.complete,
              Set(manifest.skippedPaths) == approvedSkippedPaths else {
            throw Failure.invalidSession
        }

        let lines = manifest.entries
            .sorted { $0.relativePath < $1.relativePath }
            .map {
                "\($0.kind.rawValue)\t\($0.relativePath)\t\($0.logicalBytes.map(String.init) ?? "-")"
            }

        let payload = lines.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(payload.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        return Record(
            version: 1,
            sessionID: sessionID,
            sourceVolumeUUID: sourceVolumeUUID,
            targetVolumeUUID: targetVolumeUUID,
            manifestSHA256: digest,
            approvedSkippedPaths: approvedSkippedPaths.sorted()
        )
    }

    public static func validate(
        saved: Record,
        current: Record
    ) throws {
        guard saved.version == 1, saved == current else {
            throw Failure.mismatch
        }
    }

    /// Publish an immutable session passport.
    /// The journal directory must be independently verified by the caller.
    public static func save(_ record: Record, to url: URL) throws {
        guard url.isFileURL,
              url.lastPathComponent == record.sessionID + ".session.json" else {
            throw Failure.invalidSession
        }

        let directory = url.deletingLastPathComponent()
        let fdDirectory = open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard fdDirectory >= 0 else { throw Failure.invalidSession }
        defer { _ = close(fdDirectory) }

        let data = try JSONEncoder().encode(record)
        let temporary = ".sakura-session-\(UUID().uuidString).tmp"
        let fd = openat(
            fdDirectory, temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
            mode_t(0o600)
        )
        guard fd >= 0 else { throw Failure.invalidSession }

        var isOpen = true
        defer {
            if isOpen { _ = close(fd) }
            _ = unlinkat(fdDirectory, temporary, 0)
        }

        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let count = write(fd, base.advanced(by: offset), raw.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw Failure.invalidSession }
                offset += count
            }
        }

        guard fsync(fd) == 0 else { throw Failure.invalidSession }
        guard close(fd) == 0 else {
            isOpen = false
            throw Failure.invalidSession
        }
        isOpen = false

        guard renameatx_np(
            fdDirectory, temporary,
            fdDirectory, url.lastPathComponent,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw Failure.invalidSession
        }

        guard fsync(fdDirectory) == 0 else {
            throw Failure.invalidSession
        }
    }

    public static func load(from url: URL) throws -> Record {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Record.self, from: data)
    }
}
