import XCTest
import Foundation
@testable import StorageCore

final class SakuraBackupDirectoryTests: XCTestCase {

    func testCreatesTwoIndependentDirectories() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("SakuraBackupTest-\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(at: parent)
        }

        let first = try SakuraBackupDirectory.create(in: parent)
        let second = try SakuraBackupDirectory.create(in: parent)

        XCTAssertNotEqual(first, second)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}
