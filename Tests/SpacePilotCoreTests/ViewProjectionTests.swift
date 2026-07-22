import XCTest
@testable import SpacePilotCore

final class ViewProjectionTests: XCTestCase {
    func testAIApplicationTabsRemainNestedUnderSelectedApplication() {
        XCTAssertEqual(AIApplicationTab.allCases.map(\.title), [
            "Overview", "Data & Storage", "Plugins", "Skills"
        ])
    }

    func testOverviewRecommendationsExcludeSensitiveAndManagedByDefault() {
        let items = RiskLevel.allCases.map { risk in
            ScannedItem.fixture(risk: risk, allocatedSize: 100)
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = OverviewProjection(snapshot: snapshot)

        XCTAssertTrue(projection.preselectedRecommendations.allSatisfy { $0.risk == .safe })
        XCTAssertEqual(projection.preselectedRecommendations.count, 1)
    }

    func testCategoryTotalsDoNotDoubleCountItems() {
        let item = ScannedItem.fixture(allocatedSize: 256)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.categories.reduce(0) { $0 + $1.allocatedSize }, 256)
    }

    func testOldItemsUseMetadataOnlyCutoff() {
        let old = ScannedItem.fixture(modificationDate: .distantPast)
        let recent = ScannedItem.fixture(modificationDate: .now)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [old, recent],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        XCTAssertEqual(StorageProjection(snapshot: snapshot).oldItems.map(\.id), [old.id])
    }
}
