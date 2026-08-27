import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class ApprovedProjectRootStoreTests: XCTestCase {
    func testUserDefaultsStoreLoadsVersionedPayloadAndAtomicallyReplacesRoots() throws {
        let suite = "SpacePilotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "roots"
        let store = UserDefaultsApprovedProjectRootStore(defaults: defaults, key: key)
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = ApprovedProjectRoot(canonicalRootURL: directory)

        try store.replace([root])
        var result = try store.load()
        XCTAssertEqual(result.roots, [root])
        XCTAssertTrue(result.issues.isEmpty)

        try store.replace([])
        result = try store.load()
        XCTAssertTrue(result.roots.isEmpty)
    }

    func testUserDefaultsStoreBadAndTamperedPayloadsSafelyDegrade() throws {
        let suite = "SpacePilotTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "roots"
        let store = UserDefaultsApprovedProjectRootStore(defaults: defaults, key: key)

        defaults.set(Data("not json".utf8), forKey: key)
        var result = try store.load()
        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.issues, [.invalidPayload])

        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = ApprovedProjectRoot(canonicalRootURL: directory)
        let data = try JSONEncoder().encode(root)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["id"] = "tampered"
        let payload: [String: Any] = ["version": 1, "roots": [object]]
        defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: key)

        result = try store.load()
        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.issues, [.invalidPayload])
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
