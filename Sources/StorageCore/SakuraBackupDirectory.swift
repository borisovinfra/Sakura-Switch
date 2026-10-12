import Foundation
import Darwin

/// Creates an exclusively owned directory for one backup.
/// Never reuses or overwrites an existing backup.
public enum SakuraBackupDirectory {

    public enum Failure: Error, LocalizedError {
        case invalidParent
        case cannotCreate(Int32)

        public var errorDescription: String? {
            switch self {
            case .invalidParent:
                return "Папка резервирования недоступна или небезопасна."
            case .cannotCreate(let code):
                return "Не удалось создать каталог резервной копии (код \(code))."
            }
        }
    }

    public static func create(in parent: URL) throws -> URL {
        let base = parent.standardizedFileURL

        var info = stat()
        guard lstat(base.path, &info) == 0,
              (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            throw Failure.invalidParent
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let stamp = formatter.string(from: Date())

        for _ in 0..<10 {
            let name = "Sakura-Backup_\(stamp)_\(UUID().uuidString.prefix(8))"
            let folder = base.appendingPathComponent(name, isDirectory: true)

            if mkdir(folder.path, mode_t(0o700)) == 0 {
                return folder
            }

            if errno != EEXIST {
                throw Failure.cannotCreate(errno)
            }
        }

        throw Failure.cannotCreate(EEXIST)
    }
}
