import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationCacheCleanupPolicyTests: XCTestCase {
    func testAllowsOnlyExactDirectAndContainerCacheRoots() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertNoThrow(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Caches/com.example.Editor"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor"
        ))
        XCTAssertNoThrow(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Containers/com.example.Editor/Data/Library/Caches"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor"
        ))

        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Caches/com.example.Editor/nested"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor"
        ))
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Caches/com.example.Other"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor"
        ))
    }

    func testRejectsProtectedAndMissingApplicationIdentities() {
        let home = URL(fileURLWithPath: "/Users/test")
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Caches/com.apple.Safari"),
            homeDirectory: home,
            bundleIdentifier: "com.apple.Safari"
        ))
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Caches/com.example.Editor"),
            homeDirectory: home,
            bundleIdentifier: nil
        ))
    }

    func testAllowsOnlyRecordedFixedApplicationSupportCacheLeaf() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        let relative = "Library/Application Support/Editor/User Data/Default/Code Cache"
        XCTAssertNoThrow(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: relative),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor",
            approvedRelativePath: relative
        ))
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Application Support/Editor/Documents"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor",
            approvedRelativePath: "Library/Application Support/Editor/Documents"
        ))
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: "Library/Application Support/Other/Code Cache"),
            homeDirectory: home,
            bundleIdentifier: "com.example.Editor",
            approvedRelativePath: relative
        ))
    }

    func testKnownNestedCacheRootRequiresMatchingBundleIdentifier() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        let relative = "Library/Caches/Google/Chrome"
        XCTAssertNoThrow(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: relative),
            homeDirectory: home,
            bundleIdentifier: "com.google.Chrome",
            approvedRelativePath: relative
        ))
        XCTAssertThrowsError(try ApplicationCacheCleanupPolicy.validate(
            home.appending(path: relative),
            homeDirectory: home,
            bundleIdentifier: "com.example.Chrome",
            approvedRelativePath: relative
        ))
    }
}
