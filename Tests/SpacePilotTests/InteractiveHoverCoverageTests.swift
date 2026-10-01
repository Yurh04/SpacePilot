import Foundation
import XCTest
@testable import SpacePilot
@testable import SpacePilotCore

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

    func testAssociationVisibleRowMapPreservesHeaderSlotsAndCollapsedSearchExpansion() {
        let pairs = [
            associationPair(path: "/tmp/developer", category: .developer),
            associationPair(path: "/tmp/cache", category: .cache)
        ]
        let groups = ApplicationAssociationGroup.grouped(pairs)
        let collapsedRows = ApplicationAssociationGroup.tableRowURLs(
            for: groups, collapsedCategories: [.developer], expandAll: false
        )
        XCTAssertEqual(collapsedRows, [nil, nil, URL(filePath: "/tmp/cache")])

        let searchingRows = ApplicationAssociationGroup.tableRowURLs(
            for: groups, collapsedCategories: [.developer], expandAll: true
        )
        XCTAssertEqual(searchingRows, [
            nil, URL(filePath: "/tmp/developer"), nil, URL(filePath: "/tmp/cache")
        ])
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

    func testDeveloperAINativeCollectionsHaveExplicitVisibleRowPredicates() throws {
        for (file, count) in [("DeveloperAIView", 1), ("AIApplicationDetailView", 4),
                              ("GlobalSkillsView", 3), ("GlobalPluginsView", 3),
                              ("MCPServersView", 2), ("CLIToolsView", 2), ("OtherAIToolsView", 2)] {
            let content = try source("DeveloperAI/\(file).swift")
            XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight { row in", in: content), count, file)
            XCTAssertFalse(content.contains(".nativeTableHoverHighlight()"), file)
            XCTAssertFalse(content.contains(".onTapGesture"), "\(file): preserve native selection")
        }
        let applicationDetail = try source("DeveloperAI/AIApplicationDetailView.swift")
        let overview = try XCTUnwrap(applicationDetail.range(of: "case .overview:")).lowerBound
        let storage = try XCTUnwrap(applicationDetail.range(of: "case .dataStorage:")).lowerBound
        assertNoHover(String(applicationDetail[overview..<storage]), path: "Application read-only overview")
    }

    private func assertNoHover(_ source: String, path: String) {
        XCTAssertFalse(source.contains(".interactiveHover"), path)
        XCTAssertFalse(source.contains(".nativeTableHoverHighlight"), path)
    }

    private func occurrences(of token: String, in source: String) -> Int {
        source.components(separatedBy: token).count - 1
    }

    private func associationPair(path: String, category: ItemCategory) -> ApplicationAssociationProjection {
        let item = ScannedItem(
            url: URL(filePath: path), logicalSize: 100, allocatedSize: 100,
            category: category, risk: .rebuildable, explanation: "Hover fixture"
        )
        return ApplicationAssociationProjection(
            association: ArtifactAssociation(
                itemID: item.id, applicationID: UUID(), evidence: .knownRule,
                confidence: .high, risk: .rebuildable, ownership: .owned
            ),
            item: item
        )
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
