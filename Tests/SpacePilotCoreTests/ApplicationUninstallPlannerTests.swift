import XCTest
@testable import SpacePilotCore

final class ApplicationUninstallPlannerTests: XCTestCase {
    func testCleanupReviewsBundleAndEveryNonManagedProjectedAssociationIndependently() {
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

        XCTAssertEqual(cleanup.dropFirst().map(\.item.id), [medium.id, large.id, small.id])
        XCTAssertFalse(cleanup.contains { $0.item.id == managed.id || $0.item.id == unprojected.id })
        XCTAssertEqual(cleanup.first?.item.url, app.url)
        XCTAssertEqual(cleanup.first?.item.allocatedSize, app.allocatedSize)
        XCTAssertEqual(cleanup.first?.item.category, .application)
        XCTAssertEqual(cleanup.first?.item.risk, .rebuildable)
        XCTAssertEqual(cleanup.first?.item.ownerID, app.id)
        XCTAssertEqual(cleanup.first?.ownership, .owned)
        XCTAssertNil(cleanup.first?.evidence)
        XCTAssertEqual(cleanup.dropFirst().map(\.ownership), [.possible, .owned, .owned])
        XCTAssertEqual(
            cleanup.dropFirst().map(\.evidence),
            [.vendorAndNameMatch, .exactBundleIdentifier, .exactBundleIdentifier]
        )
    }

    func testResetUsesOnlyHighConfidenceSafeProjectedAssociationsSortedBySize() {
        let appID = UUID()
        let small = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Caches/com.example.app", risk: .safe, allocatedSize: 20)
        let large = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Logs/com.example.app", risk: .rebuildable, allocatedSize: 80)
        let sensitive = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Containers/com.example.app", risk: .sensitive, allocatedSize: 100)
        let managed = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Managed/com.example.app", risk: .managed, allocatedSize: 200)
        let medium = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Application Support/Example", risk: .rebuildable, allocatedSize: 300)
        let shared = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/LaunchAgents/com.example.shared.plist", risk: .rebuildable, allocatedSize: 400)
        let associations = [
            ArtifactAssociation(itemID: small.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .safe, ownership: .owned),
            ArtifactAssociation(itemID: large.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .rebuildable, ownership: .owned),
            ArtifactAssociation(itemID: sensitive.id, applicationID: appID, evidence: .exactContainerIdentifier, confidence: .high, risk: .sensitive, ownership: .owned),
            ArtifactAssociation(itemID: managed.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .managed, ownership: .owned),
            ArtifactAssociation(itemID: medium.id, applicationID: appID, evidence: .vendorAndNameMatch, confidence: .high, risk: .rebuildable, ownership: .possible),
            ArtifactAssociation(itemID: shared.id, applicationID: appID, evidence: .knownRule, confidence: .high, risk: .rebuildable, ownership: .shared)
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
            totalSize: 1_100,
            associations: zip(associations, [small, large, sensitive, managed, medium, shared]).map {
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

        XCTAssertEqual(cleanup.filter { $0.item.id == item.id }.count, 1)
    }

    func testResetRejectsConflictingAssociationGroupRegardlessOfInputOrder() {
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/com.example.app",
            risk: .safe,
            allocatedSize: 20
        )
        let appID = UUID()
        let associations = [
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .exactBundleIdentifier,
                confidence: .high,
                risk: .safe,
                ownership: .owned
            ),
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .knownRule,
                confidence: .high,
                risk: .safe,
                ownership: .shared
            ),
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .vendorAndNameMatch,
                confidence: .medium,
                risk: .safe,
                ownership: .possible
            )
        ]

        for orderedAssociations in [associations, Array(associations.reversed())] {
            let projection = projection(
                appID: appID,
                item: item,
                associations: orderedAssociations
            )

            XCTAssertTrue(
                ApplicationUninstallPlanner().resetItems(for: projection).isEmpty
            )
        }
    }

    func testCleanupExcludesConflictingOwnershipGroupFromSelectAllRegardlessOfInputOrder() {
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/com.example.app",
            risk: .safe,
            allocatedSize: 20
        )
        let appID = UUID()
        let associations = [
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .exactBundleIdentifier,
                confidence: .high,
                risk: .safe,
                ownership: .owned
            ),
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .knownRule,
                confidence: .high,
                risk: .safe,
                ownership: .shared
            )
        ]

        for orderedAssociations in [associations, Array(associations.reversed())] {
            let review = ApplicationUninstallPlanner()
                .cleanupItems(for: projection(
                    appID: appID,
                    item: item,
                    associations: orderedAssociations
                ))
                .first { $0.item.id == item.id }

            XCTAssertEqual(review?.ownership, .shared)
            XCTAssertEqual(review?.isIncludedBySelectAll, false)
        }
    }

    func testCleanupPromotesAssociationRiskAndPlannerRequiresSensitiveConfirmation() {
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Application Support/Example/state.db",
            risk: .safe,
            allocatedSize: 20
        )
        let appID = UUID()
        let associations = [
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .exactBundleIdentifier,
                confidence: .high,
                risk: .safe,
                ownership: .owned
            ),
            ArtifactAssociation(
                itemID: item.id,
                applicationID: appID,
                evidence: .knownRule,
                confidence: .high,
                risk: .sensitive,
                ownership: .owned
            )
        ]
        let projection = projection(
            appID: appID,
            item: item,
            associations: associations
        )

        let review = ApplicationUninstallPlanner()
            .cleanupItems(for: projection)
            .first { $0.item.id == item.id }

        XCTAssertEqual(review?.item.risk, .sensitive)
        XCTAssertThrowsError(try CleanupPlanner(policy: .init(
            homeDirectory: URL(fileURLWithPath: "/Users/test"),
            allowedVolumeRoot: URL(fileURLWithPath: "/")
        )).makePlan(
            snapshotID: UUID(),
            items: [try XCTUnwrap(review?.item)],
            selectedIDs: [item.id],
            separatelyConfirmedSensitiveIDs: []
        )) { error in
            XCTAssertEqual(
                error as? CleanupPlanningError,
                .sensitiveConfirmationRequired(item.url)
            )
        }
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

    private func projection(
        appID: UUID,
        item: ScannedItem,
        associations: [ArtifactAssociation]
    ) -> ApplicationProjection {
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
        return ApplicationProjection(
            application: app,
            totalSize: app.allocatedSize + item.allocatedSize,
            associations: associations.map {
                ApplicationAssociationProjection(association: $0, item: item)
            }
        )
    }
}
