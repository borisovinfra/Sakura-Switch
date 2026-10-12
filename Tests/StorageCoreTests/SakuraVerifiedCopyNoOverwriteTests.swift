import Foundation
import XCTest
@testable import StorageCore

final class SakuraVerifiedCopyNoOverwriteTests: XCTestCase {
    func testExistingDestinationCannotBeOverwritten() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SakuraNoOverwrite-\(UUID().uuidString)", isDirectory: true)
        let sourceDir = root.appendingPathComponent("source", isDirectory: true)
        let targetDir = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = sourceDir.appendingPathComponent("existing.txt")
        let target = targetDir.appendingPathComponent("existing.txt")
        let original = Data("KEEP-ORIGINAL-DESTINATION".utf8)
        try Data("NEW-SOURCE-CONTENT".utf8).write(to: source)
        try original.write(to: target)

        XCTAssertThrowsError(try SakuraVerifiedCopy.copy(
            source: source, toDirectory: targetDir, name: "existing.txt"
        )) { error in
            guard case SakuraVerifiedCopy.Failure.alreadyExists = error else {
                XCTFail("Expected alreadyExists, got: \(error)")
                return
            }
        }
        XCTAssertEqual(try Data(contentsOf: target), original,
                       "Existing destination data must remain unchanged")
        let names = try FileManager.default.contentsOfDirectory(atPath: targetDir.path)
        XCTAssertEqual(Set(names), Set(["existing.txt"]),
                       "No partial files should remain")
    }
}
