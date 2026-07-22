import XCTest
@testable import SpacePilotCore

final class ApplicationUninstallPlannerTests: XCTestCase {
    func testResetExcludesBundleSensitiveContainersAndMediumConfidenceFiles() {
        let appID = UUID()
        let cache = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Caches/com.example.app", risk: .safe)
        let container = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Containers/com.example.app", risk: .sensitive)
        let medium = ScannedItem.fixture(id: UUID(), path: "/Users/test/Library/Application Support/Example", risk: .rebuildable)
        let associations = [
            ArtifactAssociation(itemID: cache.id, applicationID: appID, evidence: .exactBundleIdentifier, confidence: .high, risk: .safe),
            ArtifactAssociation(itemID: container.id, applicationID: appID, evidence: .exactContainerIdentifier, confidence: .high, risk: .sensitive),
            ArtifactAssociation(itemID: medium.id, applicationID: appID, evidence: .vendorAndNameMatch, confidence: .medium, risk: .rebuildable)
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
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [cache, container, medium],
            applications: [app],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let reset = ApplicationUninstallPlanner().resetItems(for: app, snapshot: snapshot)

        XCTAssertEqual(reset.map(\.id), [cache.id])
        XCTAssertFalse(reset.contains { $0.url == app.url })
    }
}
