import XCTest
@testable import StorageCore

final class StorageInspectorTests: XCTestCase {

    func testExternalDiskIdentifiers() throws {
        let disks = try StorageInspector.externalDisks()

        for disk in disks {
            XCTAssertFalse(disk.id.isEmpty)
            XCTAssertGreaterThan(disk.size, 0)
        }

        print("Sakura Storage: external disks found: \(disks.count)")

        for disk in disks {
            print("Disk: \(disk.id)")
            print("Size: \(disk.size)")
            print("Scheme: \(disk.partitionScheme)")
        }
    }
}
