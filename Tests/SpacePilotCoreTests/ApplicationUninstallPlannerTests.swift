import XCTest
@testable import SpacePilotCore

final class ApplicationUninstallPlannerTests: XCTestCase {
    func testCleanupUsesOnlyHighConfidenceProjectedAssociationsAndExcludesManagedItems() {
        let appID = UUID()
        let small = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Caches/com.example.app", risk: .safe, allocatedSize: 20)
        let large = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Logs/com.example.app", risk: .rebuildable, allocatedSize: 80)
        let managed = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Managed/com.example.app", risk: .managed, allocatedSize: 100)
        let medium = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Application Support/Example", risk: .rebuildable, allocatedSize: 200)
        let unprojected = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Caches/unprojected", risk: .safe, allocatedSize: 1_000)
        let associations = [
            ArtifactAssociation(itemID: small.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .safe, ownership: .owned),
            ArtifactAssociation(itemID: large.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .rebuildable, ownership: .owned),
            ArtifactAssociation(itemID: managed.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .managed, ownership: .owned),
            ArtifactAssociation(itemID: medium.id, applicationID: appID, evidence: .vendorAndNameMatch, confidence: .medium, risk: .rebuildable, ownership: .possible),
            ArtifactAssociation(itemID: unprojected.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .safe, ownership: .owned)
        ]
        let app = ApplicationRecord(
            id: appID,
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 100,
            associations: associations
        )
        let projection = ApplicationProjection(
            application: app,
            totalSize: 300,
            associations: [
                .init(association: associations[0], item: small),
                .init(association: associations[1], item: large),
                .init(association: associations[2], item: managed),
                .init(association: associations[3], item: medium)
            ]
        )

        let cleanup = ApplicationUninstallPlanner().cleanupItems(for: projection)

        XCTAssertEqual(cleanup.dropFirst().map(\.id), [large.id, small.id])
        XCTAssertFalse(cleanup.contains { $0.id == managed.id || $0.id == medium.id || $0.id == unprojected.id })
        XCTAssertEqual(cleanup.first?.url, app.url)
        XCTAssertEqual(cleanup.first?.allocatedSize, app.allocatedSize)
        XCTAssertEqual(cleanup.first?.category, .application)
        XCTAssertEqual(cleanup.first?.risk, .rebuildable)
        XCTAssertEqual(cleanup.first?.ownerID, app.id)
    }

    func testResetUsesOnlyHighConfidenceSafeProjectedAssociationsSortedBySize() {
        let appID = UUID()
        let small = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Caches/com.example.app", risk: .safe, allocatedSize: 20)
        let large = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Logs/com.example.app", risk: .rebuildable, allocatedSize: 80)
        let sensitive = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Containers/com.example.app", risk: .sensitive, allocatedSize: 100)
        let managed = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Managed/com.example.app", risk: .managed, allocatedSize: 200)
        let medium = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Application Support/Example", risk: .rebuildable, allocatedSize: 300)
        let associations = [
            ArtifactAssociation(itemID: small.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .safe, ownership: .owned),
            ArtifactAssociation(itemID: large.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .rebuildable, ownership: .owned),
            ArtifactAssociation(itemID: sensitive.id, applicationID: appID, evidence: .exactContainerIdentifier, confidence: .high, risk: .sensitive, ownership: .owned),
            ArtifactAssociation(itemID: managed.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .managed, ownership: .owned),
            ArtifactAssociation(itemID: medium.id, applicationID: appID, evidence: .vendorAndNameMatch, confidence: .medium, risk: .rebuildable, ownership: .possible)
        ]
        let app = ApplicationRecord(
            id: appID,
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 100,
            associations: associations
        )
        let projection = ApplicationProjection(
            application: app,
            totalSize: 700,
            associations: zip(associations, [small, large, sensitive, managed, medium]).map {
                ApplicationAssociationProjection(association: $0, item: $1)
            }
        )

        let reset = ApplicationUninstallPlanner().resetItems(for: projection)

        XCTAssertEqual(reset.map(\.id), [large.id, small.id])
        XCTAssertFalse(reset.contains { $0.url == app.url })
    }

    func testCleanupDeduplicatesProjectedAssociationsByItemID() {
        let appID = UUID()
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/com.example.app",
            risk: .safe,
            allocatedSize: 20
        )
        let first = ArtifactAssociation(
            itemID: item.id,
            applicationID: appID,
            evidence: .exactBundleIdentifier,
            confidence: .high,
            risk: .safe,
            ownership: .owned
        )
        let second = ArtifactAssociation(
            itemID: item.id,
            applicationID: appID,
            evidence: .knownRule,
            confidence: .high,
            risk: .safe,
            ownership: .owned
        )
        let app = ApplicationRecord(
            id: appID,
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 100,
            associations: [first, second]
        )
        let projection = ApplicationProjection(
            application: app,
            totalSize: 120,
            associations: [
                .init(association: first, item: item),
                .init(association: second, item: item)
            ]
        )

        let cleanup = ApplicationUninstallPlanner().cleanupItems(for: projection)

        XCTAssertEqual(cleanup.filter { $0.id == item.id }.count, 1)
    }

    func testPlannerSourceHasNoSnapshotAPIOrFullItemTraversal() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repositoryRoot.appending(path: "Sources/SpacePilotCore/Applications/ApplicationUninstallPlanner.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertFalse(source.contains("ScanSnapshot"))
        XCTAssertFalse(source.contains("snapshot.items"))
    }
}
