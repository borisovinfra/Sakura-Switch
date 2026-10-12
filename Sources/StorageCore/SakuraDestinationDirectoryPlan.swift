import Foundation

/// Read-only preparation plan. Does NOT create directories or authorize a transfer.
/// Every path is relative to a separately validated destination root.
public enum SakuraDestinationDirectoryPlan {
    public enum Failure: Error, Equatable {
        case invalidPath(String)
        case conflictingPath(String)
    }

    public struct Plan: Sendable, Equatable {
        /// Parents before children, deterministic ordering.
        public let directories: [String]
    }

    public static func make(directories: [String], files: [String]) throws -> Plan {
        func components(_ path: String) throws -> [String] {
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !parts.isEmpty, parts.allSatisfy({ component in
                !component.isEmpty && component != "." && component != ".." &&
                !component.hasPrefix("._") && !component.contains("\\") &&
                !component.contains(":") &&
                component.utf8.count <= 255 &&
                !component.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 })
            }) else { throw Failure.invalidPath(path) }
            return parts
        }

        func key(_ path: String) -> String {
            path.folding(options: [.caseInsensitive, .diacriticInsensitive],
                         locale: Locale(identifier: "en_US_POSIX"))
        }

        // Manifest entries must be unique even under case-insensitive FAT-style comparisons.
        var registered: [String: (path: String, isDirectory: Bool)] = [:]
        for (paths, isDirectory) in [(directories, true), (files, false)] {
            for path in paths {
                _ = try components(path)
                let folded = key(path)
                guard registered[folded] == nil else { throw Failure.conflictingPath(path) }
                registered[folded] = (path, isDirectory)
            }
        }

        var planned: [String: String] = [:]
        for path in directories + files {
            let parts = try components(path)
            let upperBound = registered[key(path)]?.isDirectory == true ? parts.count : parts.count - 1
            if upperBound == 0 { continue }
            for depth in 1...upperBound {
                let prefix = parts.prefix(depth).joined(separator: "/")
                let folded = key(prefix)
                if let entry = registered[folded], !entry.isDirectory {
                    throw Failure.conflictingPath(prefix)
                }
                if let prior = planned[folded], prior != prefix {
                    throw Failure.conflictingPath(prefix)
                }
                planned[folded] = prefix
            }
        }
        return Plan(directories: planned.values.sorted {
            let da = $0.split(separator: "/").count
            let db = $1.split(separator: "/").count
            return da == db ? $0 < $1 : da < db
        })
    }
}
