import Foundation
import Darwin

/// Read-only checks for a file-based backup destination.
/// Does not create, delete, format or modify files.
public enum SakuraBackupSafety {

    public enum Failure: Error, LocalizedError {
        case invalidSource
        case invalidDestination
        case destinationInsideSource
        case sourceInsideDestination
        case sameVolume
        case unsafePath

        public var errorDescription: String? {
            switch self {
            case .invalidSource:
                return "Исходный накопитель недоступен."
            case .invalidDestination:
                return "Папка назначения недоступна."
            case .destinationInsideSource:
                return "Нельзя сохранять копию внутри исходного накопителя."
            case .sourceInsideDestination:
                return "Исходный накопитель находится внутри папки назначения."
            case .sameVolume:
                return "Резервная копия должна находиться на другом накопителе."
            case .unsafePath:
                return "Обнаружен небезопасный путь или символическая ссылка."
            }
        }
    }

    private static func inspectDirectory(_ url: URL) throws -> stat {
        let path = url.standardizedFileURL.path

        guard path.hasPrefix("/") else {
            throw Failure.unsafePath
        }

        var current = ""
        var result = stat()

        for component in url.standardizedFileURL.pathComponents {
            if component == "/" {
                current = "/"
                continue
            }

            current = (current as NSString).appendingPathComponent(component)

            var info = stat()
            guard lstat(current, &info) == 0,
                  (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw Failure.unsafePath
            }

            result = info
        }

        return result
    }

    /// Validates existing directories without modifying either location.
    public static func validate(
        sourceRoot: URL,
        destinationFolder: URL
    ) throws {
        let source = sourceRoot.standardizedFileURL
        let destination = destinationFolder.standardizedFileURL

        guard FileManager.default.fileExists(atPath: source.path) else {
            throw Failure.invalidSource
        }

        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw Failure.invalidDestination
        }

        let sourceInfo = try inspectDirectory(source)
        let destinationInfo = try inspectDirectory(destination)

        let sourcePath = source.path.hasSuffix("/")
            ? source.path : source.path + "/"

        let destinationPath = destination.path.hasSuffix("/")
            ? destination.path : destination.path + "/"

        guard !destinationPath.hasPrefix(sourcePath) else {
            throw Failure.destinationInsideSource
        }

        guard !sourcePath.hasPrefix(destinationPath) else {
            throw Failure.sourceInsideDestination
        }

        guard sourceInfo.st_dev != destinationInfo.st_dev else {
            throw Failure.sameVolume
        }
    }
}
