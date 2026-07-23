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
        var selection = CleanupSelection(items: [safe, sensitive])

        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertEqual(selection.selectedBytes, 0)
        XCTAssertFalse(selection.hasSelectedSensitiveItems)

        selection.toggle(sensitive.id)

        XCTAssertEqual(selection.selectedItems.map(\.id), [sensitive.id])
        XCTAssertEqual(selection.selectedBytes, 300)
        XCTAssertTrue(selection.hasSelectedSensitiveItems)
    }

    func testSelectAllAndClearStayWithinCandidates() {
        let items = [
            item(path: "/tmp/one"),
            item(path: "/tmp/two")
        ]
        var selection = CleanupSelection(items: items)

        selection.selectAll()
        XCTAssertEqual(selection.selectedIDs, Set(items.map(\.id)))

        selection.clear()
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }

    func testToggleIgnoresUnknownIdentifiers() {
        let candidate = item(path: "/tmp/candidate")
        var selection = CleanupSelection(items: [candidate])

        selection.toggle(UUID())

        XCTAssertTrue(selection.selectedIDs.isEmpty)
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
}
