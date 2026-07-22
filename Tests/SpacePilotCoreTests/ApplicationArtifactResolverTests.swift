import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationArtifactResolverTests: XCTestCase {
    func testExactBundleIdentifierIsHighConfidence() async throws {
        let home = try TemporaryTree(files: [
            "Library/Preferences/com.example.Example.plist": 50,
            "Library/Caches/com.example.Example/cache.bin": 75
        ])
        let application = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.Example",
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 100
        )

        let result = try await ApplicationArtifactResolver().resolve(
            application: application,
            homeDirectory: home.url
        )

        XCTAssertEqual(result.associations.count, 2)
        XCTAssertTrue(result.associations.allSatisfy { $0.confidence == .high })
        XCTAssertTrue(result.associations.allSatisfy { $0.evidence == .exactBundleIdentifier })
    }

    func testUserDocumentsAreNeverSearchedAsServiceFiles() async throws {
        let home = try TemporaryTree(files: [
            "Documents/Example Project/notes.txt": 200,
            "Library/Caches/com.example.Example/cache.bin": 75
        ])
        let application = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.Example",
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 100
        )

        let result = try await ApplicationArtifactResolver().resolve(
            application: application,
            homeDirectory: home.url
        )

        XCTAssertFalse(result.items.contains { $0.url.path.contains("Documents") })
        XCTAssertEqual(result.items.count, 1)
    }
}
