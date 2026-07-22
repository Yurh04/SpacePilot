import Foundation
import XCTest
@testable import SpacePilotCore

final class VolumeScannerTests: XCTestCase {
    func testRootVolumeReportsCoherentCapacity() throws {
        let record = try VolumeScanner(root: URL(fileURLWithPath: "/")).scan()

        XCTAssertGreaterThan(record.totalCapacity, 0)
        XCTAssertGreaterThanOrEqual(record.availableCapacity, 0)
        XCTAssertLessThanOrEqual(record.availableCapacity, record.totalCapacity)
    }
}
