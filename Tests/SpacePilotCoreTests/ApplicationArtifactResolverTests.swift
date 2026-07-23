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

    func testSharedExactComponentIdentifierIsNotOwnedByEitherApplication() async throws {
        let home = try TemporaryTree(files: [
            "Library/Containers/com.example.shared.helper/state.db": 64
        ])
        let first = application(
            name: "First",
            bundleID: "com.example.first"
        )
        let second = application(
            name: "Second",
            bundleID: "com.example.second"
        )
        let sharedComponent = "com.example.shared.helper"
        let identities = [first, second].map {
            ApplicationIdentity(
                applicationID: $0.id,
                mainBundleIdentifier: $0.bundleIdentifier,
                componentBundleIdentifiers: [sharedComponent],
                teamIdentifier: "TEAM",
                applicationGroups: []
            )
        }

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
            associations.allSatisfy {
                $0.evidence == .exactBundleIdentifier
                    && $0.ownership == .shared
            }
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

    func testLaunchAgentTargetAssociatesOnlyItsUpdaterSupportDirectory() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/BrowserUpdater/Updater.app/Contents/MacOS/Updater": 31,
            "Library/Application Support/Vendor/UnrelatedService/state.db": 32
        ])
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.update.agent.plist"
        )
        let updaterSupportURL = home.url.appending(
            path: "Library/Application Support/Vendor/BrowserUpdater",
            directoryHint: .isDirectory
        )
        try EdgeAssociationFixture.writeLaunchAgent(
            at: launchAgentURL,
            target: updaterSupportURL.appending(
                path: "Updater.app/Contents/MacOS/Updater"
            )
        )
        let application = application(
            name: "Browser",
            bundleID: "com.vendor.browser"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        let paths = Set(result.items.map { $0.url.standardizedFileURL.path })
        XCTAssertTrue(paths.contains(launchAgentURL.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(updaterSupportURL.standardizedFileURL.path))
        XCTAssertFalse(paths.contains {
            $0.contains("/Vendor/UnrelatedService")
        })

        let targetItemIDs = Set(result.items.compactMap {
            [launchAgentURL, updaterSupportURL]
                .map(\.standardizedFileURL.path)
                .contains($0.url.standardizedFileURL.path) ? $0.id : nil
        })
        let targetAssociations = result.resolutions
            .flatMap(\.associations)
            .filter { targetItemIDs.contains($0.itemID) }
        XCTAssertEqual(targetItemIDs.count, 2)
        XCTAssertEqual(targetAssociations.count, 2)
        XCTAssertTrue(targetAssociations.allSatisfy {
            $0.evidence == .signedHelperRelationship
                && $0.ownership != .owned
        })
    }

    func testLaunchAgentTargetOutsideKnownSupportRootsIsIgnored() async throws {
        let home = try TemporaryTree(files: [
            "Documents/BrowserUpdater/Updater.app/Contents/MacOS/Updater": 33
        ])
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.update.agent.plist"
        )
        try EdgeAssociationFixture.writeLaunchAgent(
            at: launchAgentURL,
            target: home.url.appending(
                path: "Documents/BrowserUpdater/Updater.app/Contents/MacOS/Updater"
            )
        )
        let application = application(
            name: "Browser",
            bundleID: "com.vendor.browser"
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [identity(for: application)],
            homeDirectory: home.url
        )

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.resolutions.flatMap(\.associations).isEmpty)
    }

    func testLaunchAgentTargetWithExactComponentIdentityIsOwned() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/com.vendor.navigation.helper.app/Contents/MacOS/Helper": 34,
            "Library/Application Support/Vendor/UnrelatedService/state.db": 35
        ])
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.helper.agent.plist"
        )
        let helperURL = home.url.appending(
            path: "Library/Application Support/Vendor/com.vendor.navigation.helper.app",
            directoryHint: .isDirectory
        )
        try EdgeAssociationFixture.writeLaunchAgent(
            at: launchAgentURL,
            target: helperURL
        )
        let application = application(
            name: "Navigator",
            bundleID: "com.vendor.navigator"
        )
        let applicationIdentity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: ["com.vendor.navigation.helper"],
            teamIdentifier: "TEAM",
            applicationGroups: []
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [applicationIdentity],
            homeDirectory: home.url
        )

        let paths = Set(result.items.map { $0.url.standardizedFileURL.path })
        XCTAssertTrue(paths.contains(launchAgentURL.standardizedFileURL.path))
        XCTAssertTrue(paths.contains(helperURL.standardizedFileURL.path))
        XCTAssertFalse(paths.contains(
            home.url.appending(
                path: "Library/Application Support/Vendor"
            ).standardizedFileURL.path
        ))
        XCTAssertFalse(paths.contains {
            $0.contains("/Vendor/UnrelatedService")
        })
        let launchItemID = try XCTUnwrap(
            result.items.first {
                $0.url.standardizedFileURL == launchAgentURL.standardizedFileURL
            }?.id
        )
        let launchAssociation = try XCTUnwrap(
            result.resolutions
                .flatMap(\.associations)
                .first { $0.itemID == launchItemID }
        )
        XCTAssertEqual(
            launchAssociation.evidence,
            .signedHelperRelationship
        )
        XCTAssertEqual(launchAssociation.ownership, .owned)
    }

    func testLaunchAgentWithExactTargetsForTwoApplicationsIsShared() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/FirstUpdater/com.vendor.first.helper.app/Contents/MacOS/Helper": 36,
            "Library/Application Support/Vendor/SecondUpdater/com.vendor.second.helper.app/Contents/MacOS/Helper": 37
        ])
        let firstHelperURL = home.url.appending(
            path: "Library/Application Support/Vendor/FirstUpdater/com.vendor.first.helper.app",
            directoryHint: .isDirectory
        )
        let secondHelperURL = home.url.appending(
            path: "Library/Application Support/Vendor/SecondUpdater/com.vendor.second.helper.app",
            directoryHint: .isDirectory
        )
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.dual-helper.plist"
        )
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Program": firstHelperURL.path,
                "ProgramArguments": [secondHelperURL.path]
            ],
            format: .xml,
            options: 0
        )
        try plistData.write(to: launchAgentURL)
        let first = application(
            name: "Alpha",
            bundleID: "com.vendor.first"
        )
        let second = application(
            name: "Beta",
            bundleID: "com.vendor.second"
        )
        let identities = [
            ApplicationIdentity(
                applicationID: first.id,
                mainBundleIdentifier: first.bundleIdentifier,
                componentBundleIdentifiers: ["com.vendor.first.helper"],
                teamIdentifier: "TEAM",
                applicationGroups: []
            ),
            ApplicationIdentity(
                applicationID: second.id,
                mainBundleIdentifier: second.bundleIdentifier,
                componentBundleIdentifiers: ["com.vendor.second.helper"],
                teamIdentifier: "TEAM",
                applicationGroups: []
            )
        ]

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [first, second],
            identities: identities,
            homeDirectory: home.url
        )

        let launchItemID = try XCTUnwrap(
            result.items.first {
                $0.url.standardizedFileURL == launchAgentURL.standardizedFileURL
            }?.id
        )
        let launchAssociations = result.resolutions
            .flatMap(\.associations)
            .filter { $0.itemID == launchItemID }
        XCTAssertEqual(launchAssociations.count, 2)
        XCTAssertTrue(launchAssociations.allSatisfy {
            $0.evidence == .signedHelperRelationship
                && $0.ownership == .shared
        })
        XCTAssertNil(
            result.items.first { $0.id == launchItemID }?.ownerID
        )
        let supportPaths = Set([
            firstHelperURL.deletingLastPathComponent().standardizedFileURL.path,
            secondHelperURL.deletingLastPathComponent().standardizedFileURL.path
        ])
        let supportItemIDs = Set(result.items.compactMap {
            supportPaths.contains($0.url.standardizedFileURL.path)
                ? $0.id
                : nil
        })
        let supportAssociations = result.resolutions
            .flatMap(\.associations)
            .filter { supportItemIDs.contains($0.itemID) }
        XCTAssertEqual(supportItemIDs.count, 2)
        XCTAssertEqual(supportAssociations.count, 2)
        XCTAssertTrue(supportAssociations.allSatisfy {
            $0.evidence == .signedHelperRelationship
                && $0.ownership == .owned
        })
    }

    func testLaunchAgentTargetsSharingSupportDirectoryAreShared() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/SharedUpdater/com.vendor.first.helper.app/Contents/MacOS/Helper": 39,
            "Library/Application Support/Vendor/SharedUpdater/com.vendor.second.helper.app/Contents/MacOS/Helper": 40
        ])
        let supportURL = home.url.appending(
            path: "Library/Application Support/Vendor/SharedUpdater",
            directoryHint: .isDirectory
        )
        let firstHelperURL = supportURL.appending(
            path: "com.vendor.first.helper.app",
            directoryHint: .isDirectory
        )
        let secondHelperURL = supportURL.appending(
            path: "com.vendor.second.helper.app",
            directoryHint: .isDirectory
        )
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.shared-helper.plist"
        )
        try FileManager.default.createDirectory(
            at: launchAgentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "Program": firstHelperURL.path,
                "ProgramArguments": [secondHelperURL.path]
            ],
            format: .xml,
            options: 0
        )
        try plistData.write(to: launchAgentURL)
        let first = application(
            name: "Alpha",
            bundleID: "com.vendor.first"
        )
        let second = application(
            name: "Beta",
            bundleID: "com.vendor.second"
        )
        let identities = [
            ApplicationIdentity(
                applicationID: first.id,
                mainBundleIdentifier: first.bundleIdentifier,
                componentBundleIdentifiers: ["com.vendor.first.helper"],
                teamIdentifier: "TEAM",
                applicationGroups: []
            ),
            ApplicationIdentity(
                applicationID: second.id,
                mainBundleIdentifier: second.bundleIdentifier,
                componentBundleIdentifiers: ["com.vendor.second.helper"],
                teamIdentifier: "TEAM",
                applicationGroups: []
            )
        ]

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [first, second],
            identities: identities,
            homeDirectory: home.url
        )

        let supportItem = try XCTUnwrap(
            result.items.first {
                $0.url.standardizedFileURL == supportURL.standardizedFileURL
            }
        )
        let supportAssociations = result.resolutions
            .flatMap(\.associations)
            .filter { $0.itemID == supportItem.id }
        XCTAssertEqual(supportAssociations.count, 2)
        XCTAssertTrue(supportAssociations.allSatisfy {
            $0.evidence == .signedHelperRelationship
                && $0.ownership == .shared
        })
        XCTAssertNil(supportItem.ownerID)
    }

    func testExactLaunchTargetIdentityPreservesPunctuation() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/com.vendor.foobar.app/Contents/MacOS/Helper": 38
        ])
        let targetURL = home.url.appending(
            path: "Library/Application Support/Vendor/com.vendor.foobar.app",
            directoryHint: .isDirectory
        )
        let launchAgentURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.punctuation.plist"
        )
        try EdgeAssociationFixture.writeLaunchAgent(
            at: launchAgentURL,
            target: targetURL
        )
        let application = application(
            name: "Voyager",
            bundleID: "com.vendor.voyager"
        )
        let applicationIdentity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: ["com.vendor.foo-bar"],
            teamIdentifier: "TEAM",
            applicationGroups: []
        )

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [application],
            identities: [applicationIdentity],
            homeDirectory: home.url
        )

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.resolutions.flatMap(\.associations).isEmpty)
    }

    func testLaunchItemReaderExtractsProgramAndFirstProgramArgument() throws {
        let home = try TemporaryTree(files: [:])
        let plistURL = home.url.appending(
            path: "Library/LaunchAgents/com.vendor.reader.plist"
        )
        let programURL = home.url.appending(
            path: "Library/Application Support/Vendor/Program"
        )
        let firstArgumentURL = home.url.appending(
            path: "Library/Application Support/Vendor/FirstArgument"
        )
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "Program": programURL.path,
                "ProgramArguments": [
                    firstArgumentURL.path,
                    "--ignored"
                ]
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL)

        let targets = LaunchItemAssociationReader().targetURLs(in: plistURL)

        XCTAssertEqual(
            targets,
            [
                programURL.standardizedFileURL,
                firstArgumentURL.standardizedFileURL
            ]
        )
    }

    func testEdgeFixtureCoversDeepCategoriesAndSharedAuthenticationGroups() async throws {
        let fixture = try EdgeAssociationFixture.make()

        let result = try await ApplicationArtifactResolver().resolve(
            applications: [fixture.application],
            identities: [fixture.identity],
            homeDirectory: fixture.tree.url
        )

        let paths = Set(result.items.map(\.url.path))
        XCTAssertTrue(paths.contains {
            $0.hasSuffix("Library/HTTPStorages/com.microsoft.edgemac")
        })
        XCTAssertTrue(paths.contains {
            $0.hasSuffix("Library/WebKit/com.microsoft.edgemac")
        })
        XCTAssertTrue(paths.contains {
            $0.hasSuffix("Library/Application Scripts/com.microsoft.edgemac.wdgExtension")
        })
        XCTAssertTrue(paths.contains(fixture.launchAgentURL.path))
        XCTAssertTrue(paths.contains(fixture.updaterSupportURL.path))

        let itemsByID = Dictionary(
            uniqueKeysWithValues: result.items.map { ($0.id, $0) }
        )
        let ownership = result.resolutions
            .flatMap(\.associations)
            .reduce(into: [String: AssociationOwnership]()) {
                guard let item = itemsByID[$1.itemID] else { return }
                $0[item.url.lastPathComponent] = $1.ownership
            }
        XCTAssertEqual(
            ownership["UBF8T346G9.com.microsoft.oneauth"],
            .shared
        )
        XCTAssertEqual(
            ownership["UBF8T346G9.com.microsoft.entrabroker"],
            .shared
        )
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
