import Foundation
import XCTest
@testable import SpacePilot
@testable import SpacePilotCore

final class ApplicationAssociationGroupingTests: XCTestCase {
    func testGroupsUseCategoryOrderAndLargestItemFirst() throws {
        let applicationID = UUID()
        let cacheSmall = pair(
            applicationID: applicationID,
            path: "/tmp/cache-small",
            category: .cache,
            allocatedSize: 100
        )
        let cacheLarge = pair(
            applicationID: applicationID,
            path: "/tmp/cache-large",
            category: .cache,
            allocatedSize: 300
        )
        let developer = pair(
            applicationID: applicationID,
            path: "/tmp/developer",
            category: .developer,
            allocatedSize: 200
        )

        let groups = ApplicationAssociationGroup.grouped([
            cacheSmall, cacheLarge, developer
        ])

        XCTAssertEqual(groups.map(\.category), [.developer, .cache])
        XCTAssertEqual(groups[0].allocatedSize, 200)
        XCTAssertEqual(groups[1].allocatedSize, 400)
        XCTAssertEqual(
            groups[1].pairs.map { $0.item.url.lastPathComponent },
            ["cache-large", "cache-small"]
        )
    }

    func testEmptyAssociationsProduceNoSections() {
        XCTAssertTrue(ApplicationAssociationGroup.grouped([]).isEmpty)
    }

    private func pair(
        applicationID: UUID,
        path: String,
        category: ItemCategory,
        allocatedSize: Int64
    ) -> ApplicationAssociationProjection {
        let item = ScannedItem(
            url: URL(filePath: path),
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            category: category,
            risk: .rebuildable,
            explanation: "Fixture"
        )
        return ApplicationAssociationProjection(
            association: ArtifactAssociation(
                itemID: item.id,
                applicationID: applicationID,
                evidence: .knownRule,
                confidence: .high,
                risk: .rebuildable,
                ownership: .owned
            ),
            item: item
        )
    }
}
