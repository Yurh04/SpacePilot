import Foundation
import XCTest

final class InteractiveHoverCoverageTests: XCTestCase {
    func testApplicationCollectionsInstallHoverAtBothNativeLists() throws {
        let source = try source("Applications/ApplicationsView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 2)
        XCTAssertTrue(source.contains("applications.indices.contains(row)"))
        XCTAssertTrue(source.contains("rowURLs.indices.contains(row)"))
    }

    func testApplicationPlainSearchClearButtonHasControlHover() throws {
        let source = try source("Applications/ApplicationsView.swift")
        XCTAssertTrue(source.contains(".buttonStyle(.plain)\n                        .interactiveHover(cornerRadius: 6)"))
        XCTAssertEqual(occurrences(of: ".interactiveHover", in: source), 1)
    }

    func testStorageInstallsHoverAtCategoryListAndBothTables() throws {
        let source = try source("Storage/StorageView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 3)
        XCTAssertTrue(source.contains("row > 0 && row <= projection.categories.count + 1"),
            "Category headings and the read-only unattributed row must be excluded")
        XCTAssertTrue(source.contains("visibleItems.indices.contains(row)"))
        XCTAssertTrue(source.contains("visibleChanges.indices.contains(row)"))
    }

    func testCleanupConfirmationUsesVisibleItemsAndSuppressesExecutingRows() throws {
        let source = try source("Shared/CleanupConfirmationView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 1)
        XCTAssertTrue(source.contains("!isExecuting && items.indices.contains(row)"))
    }

    func testHistoryMapsExpandedVisibleRowsAndOnlyRevealableOutcomes() throws {
        let source = try source("History/CleanupHistoryView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 1)
        XCTAssertTrue(source.contains("expandedTransactionIDs.contains(transaction.id)"))
        XCTAssertTrue(source.contains("hoverRows.indices.contains(row) && hoverRows[row]"))
        XCTAssertTrue(source.contains("FinderReveal.cleanupHistoryURL("))
    }

    func testReadOnlyMetricsCapacityAndSummariesHaveNoHover() throws {
        for (path, marker) in [
            ("Applications/ApplicationsView.swift", "private struct ApplicationMetric:"),
            ("Storage/StorageView.swift", "private struct StorageUnattributedRow:"),
            ("Storage/StorageView.swift", "private struct StorageChangeSummary:")
        ] {
            let content = try source(path)
            let start = try XCTUnwrap(content.range(of: marker)).lowerBound
            let remaining = content[start...]
            let end = remaining.dropFirst(marker.count).range(of: "\nprivate ")?.lowerBound
                ?? content.endIndex
            assertNoHover(String(content[start..<end]), path: path)
        }
        assertNoHover(try source("Storage/StorageCapacityOverview.swift"),
            path: "Storage/StorageCapacityOverview.swift")
    }

    private func assertNoHover(_ source: String, path: String) {
        XCTAssertFalse(source.contains(".interactiveHover"), path)
        XCTAssertFalse(source.contains(".nativeTableHoverHighlight"), path)
    }

    private func occurrences(of token: String, in source: String) -> Int {
        source.components(separatedBy: token).count - 1
    }

    private func source(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appending(path: "Sources/SpacePilot/Views/\(path)"),
            encoding: .utf8)
    }
}
