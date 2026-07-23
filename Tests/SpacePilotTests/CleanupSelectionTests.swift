import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class CleanupSelectionTests: XCTestCase {
    func testSelectionStartsEmptyAndTotalsOnlyExplicitSelections() {
        let safe = item(path: "/tmp/safe", risk: .safe, allocatedSize: 100)
        let sensitive = item(
            path: "/tmp/sensitive",
            risk: .sensitive,
            allocatedSize: 300
        )
        var selection = CleanupSelection(items: [
            reviewItem(safe),
            reviewItem(sensitive)
        ])

        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertEqual(selection.selectedBytes, 0)
        XCTAssertFalse(selection.hasSelectedSensitiveItems)

        selection.toggle(sensitive.id)

        XCTAssertEqual(selection.selectedItems.map(\.item.id), [sensitive.id])
        XCTAssertEqual(selection.selectedBytes, 300)
        XCTAssertTrue(selection.hasSelectedSensitiveItems)
    }

    func testSelectAllAndClearStayWithinCandidates() {
        let items = [
            item(path: "/tmp/one"),
            item(path: "/tmp/two")
        ]
        var selection = CleanupSelection(items: items.map { reviewItem($0) })

        selection.selectAll()
        XCTAssertEqual(selection.selectedIDs, Set(items.map(\.id)))

        selection.clear()
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testToggleIgnoresUnknownIdentifiers() {
        let candidate = item(path: "/tmp/candidate")
        var selection = CleanupSelection(items: [reviewItem(candidate)])

        selection.toggle(UUID())

        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testSelectAllIncludesOnlyOwnedReviewItems() {
        var selection = CleanupSelection(items: [
            reviewItem(item(path: "/tmp/owned"), ownership: .owned),
            reviewItem(item(path: "/tmp/shared"), ownership: .shared),
            reviewItem(item(path: "/tmp/possible"), ownership: .possible)
        ])

        selection.selectAll()

        XCTAssertEqual(selection.selectedIDs, [selection.items[0].id])
    }

    func testSelectAllPreservesManuallySelectedSharedReviewItems() {
        var selection = CleanupSelection(items: [
            reviewItem(item(path: "/tmp/owned"), ownership: .owned),
            reviewItem(item(path: "/tmp/shared"), ownership: .shared)
        ])
        selection.toggle(selection.items[1].id)

        selection.selectAll()

        XCTAssertEqual(selection.selectedIDs, Set(selection.items.map(\.id)))
    }

    func testEffectiveSensitiveRiskRequiresSelectionConfirmation() {
        let safeItem = item(path: "/tmp/association-sensitive", risk: .safe)
        let review = CleanupReviewItem(
            item: safeItem,
            ownership: .owned,
            evidence: .knownRule,
            effectiveRisk: .sensitive
        )
        var selection = CleanupSelection(items: [review])

        selection.toggle(review.id)

        XCTAssertEqual(review.item.risk, .sensitive)
        XCTAssertTrue(selection.hasSelectedSensitiveItems)
    }

    private func item(
        path: String,
        risk: RiskLevel = .safe,
        allocatedSize: Int64 = 0
    ) -> ScannedItem {
        ScannedItem(
            url: URL(fileURLWithPath: path),
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            category: .cache,
            risk: risk,
            explanation: "Fixture"
        )
    }

    private func reviewItem(
        _ item: ScannedItem,
        ownership: AssociationOwnership = .owned
    ) -> CleanupReviewItem {
        CleanupReviewItem(item: item, ownership: ownership, evidence: nil)
    }
}
