import Foundation
import XCTest
@testable import SpacePilotCore

final class PathSafetyPolicyTests: XCTestCase {
    func testRejectsBroadAndSystemPaths() {
        let policy = PathSafetyPolicy(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            allowedVolumeRoot: URL(fileURLWithPath: "/")
        )

        for path in ["/", "/System", "/Library", "/Users/test", "/Applications"] {
            XCTAssertThrowsError(try policy.validate(URL(fileURLWithPath: path)), path)
        }
    }

    func testAllowsDescendantCacheFile() throws {
        let policy = PathSafetyPolicy(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            allowedVolumeRoot: URL(fileURLWithPath: "/")
        )
        let candidate = URL(fileURLWithPath: "/Users/test/Library/Caches/app/file")

        XCTAssertEqual(try policy.validate(candidate).path, candidate.path)
    }

    func testRejectsPathOutsideAllowedVolumeRoot() {
        let policy = PathSafetyPolicy(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            allowedVolumeRoot: URL(fileURLWithPath: "/Users/test")
        )

        XCTAssertThrowsError(try policy.validate(URL(fileURLWithPath: "/Volumes/External/file")))
    }
}
