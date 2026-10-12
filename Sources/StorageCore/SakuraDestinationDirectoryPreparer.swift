import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Creates only directories listed in a previously validated plan.
/// Uses dirfd-relative operations; never follows symbolic links.
/// Does not authorize any transfer, file writes, or disk selection.
public enum SakuraDestinationDirectoryPreparer {
    public enum Failure: Error, Equatable {
        case unsafeRoot
        case invalidComponent(String)
        case unsafeEntry(String)
        case io(String, Int32)
    }

    /// The root must already exist. No entry outside this root is created.
    /// Existing directories are accepted, but links and non-directories are rejected.
    @discardableResult
    public static func prepare(plan: SakuraDestinationDirectoryPlan.Plan, root: URL) throws -> Int {
        let rootPath = root.path
        guard root.isFileURL, rootPath.hasPrefix("/"), rootPath != "/" else {
            throw Failure.unsafeRoot
        }
        var ancestor = ""
        for piece in URL(fileURLWithPath: rootPath).pathComponents {
            if piece == "/" { ancestor = "/"; continue }
            ancestor = (ancestor == "/" ? "/" : ancestor + "/") + piece
            var st = stat()
            guard lstat(ancestor, &st) == 0,
                  (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw Failure.unsafeRoot
            }
        }
        let rootFD = open(rootPath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw Failure.unsafeRoot }
        defer { close(rootFD) }
        var created = 0
        for relative in plan.directories {
            let parts = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ part in
                !part.isEmpty && part != "." && part != ".." &&
                !part.contains("/") && !part.contains("\\") && !part.contains(":") &&
                !part.hasPrefix("._") && part.utf8.count <= 255 &&
                !part.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
            }) else { throw Failure.invalidComponent(relative) }
            let first = dup(rootFD)
            guard first >= 0 else { throw Failure.io(relative, errno) }
            var fd = first
            defer { close(fd) }
            for part in parts {
                var child = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if child < 0 {
                    guard errno == ENOENT else { throw Failure.unsafeEntry(relative) }
                    if mkdirat(fd, part, mode_t(0o700)) == 0 {
                        created += 1
                    } else if errno != EEXIST {
                        throw Failure.io(relative, errno)
                    }
                    child = openat(fd, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw Failure.unsafeEntry(relative) }
                }
                close(fd)
                fd = child
            }
        }
        return created
    }
}
