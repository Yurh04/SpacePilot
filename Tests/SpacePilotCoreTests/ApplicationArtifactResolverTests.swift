import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationArtifactResolverTests: XCTestCase {
    func testExactBundleIdentifierIsHighConfidenceAndOwned() async throws {
        let home = try TemporaryTree(files: [
            "Library/Preferences/com.example.Example.plist": 50,
            "Library/Caches/com.example.Example/cache.bin": 75
        ])
        let application = application(
            name: "Example",
            bundleID: "com.example.Example"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        let resolution = try XCTUnwrap(result.resolutions.first)
        XCTAssertEqual(resolution.associations.count, 2)
        XCTAssertTrue(
            resolution.associations.allSatisfy {
                $0.confidence == .high
                    && $0.evidence == .exactBundleIdentifier
                    && $0.ownership == .owned
            }
        )
        XCTAssertTrue(
            result.items.allSatisfy { $0.ownerID == application.id }
        )
    }

    func testSharedApplicationGroupIsNotOwnedByEitherApplication() async throws {
        let home = try TemporaryTree(files: [
            "Library/Group Containers/TEAM.shared/token.db": 64
        ])
        let first = application(
            id: UUID(),
            name: "First",
            bundleID: "com.example.first"
        )
        let second = application(
            id: UUID(),
            name: "Second",
            bundleID: "com.example.second"
        )
        let identities = [
            identity(for: first, groups: ["TEAM.shared"]),
            identity(for: second, groups: ["TEAM.shared"])
        ]

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [first, second],
            identities: identities,
            homeDirectory: home.url
        )

        let item = try XCTUnwrap(result.items.first)
        let associations = result.resolutions.flatMap(\.associations)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(associations.count, 2)
        XCTAssertEqual(Set(associations.map(\.itemID)), [item.id])
        XCTAssertTrue(
            associations.allSatisfy { $0.ownership == .shared }
        )
        XCTAssertNil(item.ownerID)
    }

    func testDeepServiceRootsAndEmbeddedComponentsAreResolved() async throws {
        let home = try TemporaryTree(files: [
            "Library/HTTPStorages/com.example.Product/http.db": 11,
            "Library/WebKit/com.example.Product/WebsiteData/data.db": 12,
            "Library/Application Scripts/com.example.Product/script.scpt": 13,
            "Library/Application Support/CrashReporter/com.example.Product/crash.log": 14,
            "Library/Logs/DiagnosticReports/com.example.Product/report.diag": 15,
            "Library/Containers/com.example.Product.Widget/widget.db": 16
        ])
        let application = application(
            name: "Product",
            bundleID: "com.example.Product"
        )
        let applicationIdentity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: ["com.example.Product.Widget"],
            teamIdentifier: "TEAM",
            applicationGroups: []
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [applicationIdentity],
            homeDirectory: home.url
        )

        XCTAssertEqual(
            Set(result.items.map { $0.url.path.replacingOccurrences(
                of: home.url.path + "/",
                with: ""
            ) }),
            [
                "Library/HTTPStorages/com.example.Product",
                "Library/WebKit/com.example.Product",
                "Library/Application Scripts/com.example.Product",
                "Library/Application Support/CrashReporter/com.example.Product",
                "Library/Logs/DiagnosticReports/com.example.Product",
                "Library/Containers/com.example.Product.Widget"
            ]
        )
        XCTAssertEqual(result.items.count, 6)
        XCTAssertEqual(result.resolutions.flatMap(\.associations).count, 6)
        XCTAssertEqual(
            result.items.first {
                $0.url.path.contains("/CrashReporter/")
            }?.category,
            .log
        )
        XCTAssertEqual(
            result.items.first {
                $0.url.path.contains("/DiagnosticReports/")
            }?.category,
            .log
        )
    }

    func testNestedVendorProductEmitsMatchedParentWithoutDescendants() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/Product/state.db": 21,
            "Library/Application Support/Vendor/Product/Product/duplicate.db": 22
        ])
        let application = application(
            name: "Product",
            bundleID: "com.example.Product"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(
            result.items.first?.url.standardizedFileURL.path,
            home.url.appending(
                path: "Library/Application Support/Vendor/Product"
            ).standardizedFileURL.path
        )
        XCTAssertEqual(
            result.resolutions.flatMap(\.associations).first?.ownership,
            .possible
        )
        XCTAssertNil(result.items.first?.ownerID)
    }

    func testConfiguredServiceRootIsNotEmittedAsNamedApplicationParent() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/CrashReporter/com.example.CrashReporter/crash.log": 23
        ])
        let application = application(
            name: "CrashReporter",
            bundleID: "com.example.CrashReporter"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(
            result.items.first?.url.standardizedFileURL.path,
            home.url.appending(
                path: "Library/Application Support/CrashReporter/com.example.CrashReporter"
            ).standardizedFileURL.path
        )
    }

    func testUserDocumentsAreNeverSearchedAsServiceFiles() async throws {
        let home = try TemporaryTree(files: [
            "Documents/Example Project/notes.txt": 200,
            "Library/Caches/com.example.Example/cache.bin": 75
        ])
        let application = application(
            name: "Example",
            bundleID: "com.example.Example"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        XCTAssertFalse(result.items.contains { $0.url.path.contains("Documents") })
        XCTAssertEqual(result.items.count, 1)
    }

    private func application(
        id: UUID = UUID(),
        name: String,
        bundleID: String
    ) -> ApplicationRecord {
        ApplicationRecord(
            id: id,
            name: name,
            bundleIdentifier: bundleID,
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            executableURL: nil,
            allocatedSize: 100
        )
    }

    private func identity(
        for application: ApplicationRecord,
        groups: Set<String> = []
    ) -> ApplicationIdentity {
        ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: [],
            teamIdentifier: "TEAM",
            applicationGroups: groups
        )
    }
}
