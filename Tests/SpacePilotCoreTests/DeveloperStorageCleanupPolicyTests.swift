import Foundation
import XCTest
@testable import SpacePilotCore

final class DeveloperStorageCleanupPolicyTests: XCTestCase {
    func testAllowsOnlyExactCatalogPath() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertNoThrow(try DeveloperStorageCleanupPolicy.validate(
            home.appending(path: ".m2/repository"),
            homeDirectory: home,
            approvedRelativePath: ".m2/repository"
        ))
        XCTAssertThrowsError(try DeveloperStorageCleanupPolicy.validate(
            home.appending(path: ".m2"),
            homeDirectory: home,
            approvedRelativePath: ".m2"
        ))
        XCTAssertThrowsError(try DeveloperStorageCleanupPolicy.validate(
            home.appending(path: ".m2/repository/other"),
            homeDirectory: home,
            approvedRelativePath: ".m2/repository"
        ))
    }
}
