import XCTest
@testable import SpacePilotCore

final class ViewProjectionTests: XCTestCase {
    func testAppSnapshotProjectionBuildsAllPageInputs() throws {
        let plugin = PluginRecord(
            name: "product-design",
            version: "0.1.52",
            url: URL(fileURLWithPath: "/tmp/product-design"),
            source: "openai-curated-remote",
            allocatedSize: 500,
            skillIDs: [],
            dependencies: []
        )
        let codex = AIApplicationRecord.fixture(pluginIDs: [plugin.id])
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [ScannedItem.fixture(allocatedSize: 100)],
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [],
            coverage: .complete,
            pluginDiagnostics: []
        )

        let projection = AppSnapshotProjection(snapshot: snapshot)

        XCTAssertEqual(projection.snapshotID, snapshot.id)
        XCTAssertEqual(projection.developerAI.applications.first?.plugins.map(\.name), ["product-design"])
        XCTAssertLessThanOrEqual(projection.storage.largestItems.count, StorageProjection.itemDisplayLimit)
    }

    func testOverviewAndStorageOutputsStayBounded() {
        let items = (0..<500).map { ScannedItem.fixture(allocatedSize: Int64($0)) }
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

        let projection = AppSnapshotProjection(snapshot: snapshot)

        XCTAssertEqual(projection.overview.recommendations.count, 8)
        XCTAssertEqual(projection.overview.recommendations.map(\.allocatedSize), Array((492..<500).reversed()).map(Int64.init))
        XCTAssertEqual(projection.overview.reclaimableBytes, items.reduce(0) { $0 + $1.allocatedSize })
        XCTAssertEqual(projection.storage.largestItems.count, 100)
    }

    func testDeveloperAIProjectionAggregatesIndexedCollectionsWithoutDoubleCountingPluginSkills() throws {
        let pluginID = UUID()
        let childSkill = SkillRecord.fixture(allocatedSize: 40, parentPluginID: pluginID)
        let standaloneSkill = SkillRecord.fixture(allocatedSize: 60)
        let plugin = PluginRecord(
            id: pluginID,
            name: "plugin",
            version: "1",
            url: URL(fileURLWithPath: "/tmp/plugin"),
            source: "fixture",
            allocatedSize: 500,
            skillIDs: [childSkill.id]
        )
        let item = ScannedItem.fixture(allocatedSize: 100)
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            itemIDs: [item.id],
            pluginIDs: [plugin.id],
            skillIDs: [childSkill.id, standaloneSkill.id],
            applicationAllocatedSize: 10
        )
        let developerItem = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/developer"),
            logicalSize: 200,
            allocatedSize: 200,
            category: .developer,
            risk: .safe,
            explanation: "Fixture"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [developerItem, item],
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [childSkill, standaloneSkill],
            coverage: .complete,
            pluginDiagnostics: ["Invalid manifest"]
        )

        let projection = DeveloperAIProjection(snapshot: snapshot)
        let application = try XCTUnwrap(projection.applications.first)

        XCTAssertEqual(projection.developerBytes, 200)
        XCTAssertEqual(projection.pluginDiagnostics, ["Invalid manifest"])
        XCTAssertEqual(application.dataItems.map(\.id), [item.id])
        XCTAssertEqual(application.plugins.map(\.id), [plugin.id])
        XCTAssertEqual(Set(application.skills.map(\.id)), [childSkill.id, standaloneSkill.id])
        XCTAssertEqual(application.totalSize, 670)
    }

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

    func testStorageProjectionBoundsOldItemResultsForDisplay() {
        let items = (0...StorageProjection.itemDisplayLimit).map { index in
            ScannedItem.fixture(
                allocatedSize: Int64(index),
                modificationDate: Date.distantPast.addingTimeInterval(TimeInterval(index))
            )
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

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.oldItems.count, StorageProjection.itemDisplayLimit)
    }

    func testApplicationListProjectionAggregatesRelatedSizesBeforeSorting() {
        let largerID = UUID()
        let smallerID = UUID()
        let larger = ApplicationRecord(
            id: largerID,
            name: "Larger",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Larger.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let smaller = ApplicationRecord(
            id: smallerID,
            name: "Smaller",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Smaller.app"),
            executableURL: nil,
            allocatedSize: 200
        )
        let items = [
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/larger-cache"),
                logicalSize: 900,
                allocatedSize: 900,
                category: .cache,
                risk: .safe,
                ownerID: largerID,
                explanation: "Fixture"
            ),
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/unowned"),
                logicalSize: 10_000,
                allocatedSize: 10_000,
                category: .cache,
                risk: .safe,
                explanation: "Fixture"
            )
        ]
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [smaller, larger],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = ApplicationListProjection(snapshot: snapshot, searchText: "")

        XCTAssertEqual(projection.applications.map(\.id), [largerID, smallerID])
        XCTAssertEqual(projection.totalSize(for: largerID), 1_000)
        XCTAssertEqual(projection.totalSize(for: smallerID), 200)
    }

    func testApplicationListProjectionFiltersPreviouslyAggregatedApplications() {
        let alpha = ApplicationRecord(
            name: "Alpha",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Alpha.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let beta = ApplicationRecord(
            name: "Beta",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Beta.app"),
            executableURL: nil,
            allocatedSize: 200
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [alpha, beta],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = ApplicationListProjection(snapshot: snapshot, searchText: "ignored")

        XCTAssertEqual(projection.applications.map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(projection.filtered(by: "alp").map(\.id), [alpha.id])
        XCTAssertEqual(projection.filtered(by: "").map(\.id), [beta.id, alpha.id])
    }
}
