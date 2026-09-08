import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationVolatileArtifactFinderTests: XCTestCase {
    func testFindsOnlyImmediateSignedBundleNamespaceArtifacts() throws {
        let tree = try TemporaryTree(files: [
            "UserTemporary/C/com.google.Chrome.helper/cache.bin": 11,
            "UserTemporary/T/com.google.Chrome.ItSffG/state": 12,
            "UserTemporary/X/com.google.Chrome.code_sign_clone/Chrome.app/file": 13,
            "UserTemporary/C/com.google.Chrome.helper.plugin.session/data": 14,
            "UserTemporary/C/com.google.ChromeCanary/cache.bin": 15,
            "UserTemporary/C/unrelated/com.google.Chrome/nested.bin": 16
        ])
        let temporaryDirectory = tree.url.appending(
            path: "UserTemporary/T",
            directoryHint: .isDirectory
        )
        let application = ApplicationRecord(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            version: "1.0",
            url: tree.url.appending(path: "Applications/Google Chrome.app"),
            executableURL: nil,
            allocatedSize: 1
        )
        let identity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: "com.google.Chrome",
            componentBundleIdentifiers: [
                "com.google.Chrome.helper.plugin"
            ],
            teamIdentifier: "EQHXZ8M8AV",
            applicationGroups: []
        )

        let candidates = try ApplicationVolatileArtifactFinder(
            temporaryDirectory: temporaryDirectory
        ).candidates(for: application, identity: identity)

        XCTAssertEqual(
            Set(candidates.map(\.url.lastPathComponent)),
            [
                "com.google.Chrome.helper",
                "com.google.Chrome.ItSffG",
                "com.google.Chrome.code_sign_clone",
                "com.google.Chrome.helper.plugin.session"
            ]
        )
        XCTAssertTrue(candidates.allSatisfy {
            $0.confidence == .high && $0.ownership == .owned
        })
        XCTAssertEqual(
            candidates.first {
                $0.url.lastPathComponent
                    == "com.google.Chrome.helper.plugin.session"
            }?.evidence,
            .signedHelperRelationship
        )
        XCTAssertFalse(candidates.contains {
            $0.url.lastPathComponent == "com.google.ChromeCanary"
                || $0.url.lastPathComponent == "unrelated"
        })
    }

    func testIgnoresSymlinksAndInvalidBundleIdentifiers() throws {
        let tree = try TemporaryTree(files: [
            "UserTemporary/C/real/data": 21
        ])
        let temporaryDirectory = tree.url.appending(
            path: "UserTemporary/T",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: tree.url.appending(path: "UserTemporary/X"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: tree.url.appending(
                path: "UserTemporary/X/com.example.App.escape"
            ),
            withDestinationURL: tree.url.appending(
                path: "UserTemporary/C/real"
            )
        )
        let application = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "../invalid",
            version: nil,
            url: tree.url.appending(path: "Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 1
        )
        let identity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: "com.example.App",
            componentBundleIdentifiers: [],
            teamIdentifier: nil,
            applicationGroups: []
        )

        let candidates = try ApplicationVolatileArtifactFinder(
            temporaryDirectory: temporaryDirectory
        ).candidates(for: application, identity: identity)

        XCTAssertTrue(candidates.isEmpty)
    }
}
