import Foundation
import XCTest

final class StorageWorkbenchArchitectureTests: XCTestCase {
    func testStorageViewConnectsCategoryAndTableSelection() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("@State private var categorySelection"))
        XCTAssertTrue(source.contains("@State private var selectedItemIDs"))
        XCTAssertTrue(source.contains("projection.items("))
        XCTAssertTrue(source.contains("sortOrder: $itemSortOrder"))
        XCTAssertTrue(source.contains("safeSelectedItems"))
    }

    func testStorageViewShowsDiskMetricsAndVisibleCleanupAction() throws {
        let source = try storageViewSource()
        let capacitySource = try storageCapacitySource()

        XCTAssertTrue(capacitySource.contains("projection.totalCapacity"))
        XCTAssertTrue(capacitySource.contains("projection.availableBytes"))
        XCTAssertTrue(capacitySource.contains("StorageSegmentedCapacityBar"))
        XCTAssertTrue(capacitySource.contains("projection.unattributedBytes"))
        XCTAssertTrue(capacitySource.contains("projection.capacityCategories"))
        XCTAssertTrue(source.contains(
            "reviewButton(items: safeSelectedItems)"
        ))
    }

    func testStorageTableNameColumnShowsTheSystemFileIcon() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("FileSystemItemIcon(url: item.url)"))
    }

    func testRecentChangesExposesTimeAndKindFilters() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("case recent"))
        XCTAssertTrue(source.contains("StorageChangeTimeRange = .week"))
        XCTAssertTrue(source.contains("StorageChangeKindFilter = .all"))
        XCTAssertTrue(source.contains("StorageChangeProjection("))
        XCTAssertTrue(source.contains("sortOrder: $changeSortOrder"))
        XCTAssertTrue(source.contains("StorageChangeSafetyFilter = .all"))
        XCTAssertTrue(source.contains("safeOnly: changeSafetyFilter == .safe"))
        XCTAssertTrue(source.contains("entry.isSafeToClean"))
        XCTAssertTrue(source.contains("shield.checkered"))
        XCTAssertTrue(source.contains("workspaceNavigationToolbar(visibleItemCount:"))
        XCTAssertEqual(
            source.components(separatedBy: "workspaceNavigationToolbar(visibleItemCount:").count - 1,
            1,
            "The mode picker toolbar must stay outside the mode-specific content branches"
        )
        XCTAssertTrue(source.contains("workspaceActionSlotWidth: CGFloat = 150"))
        XCTAssertTrue(source.contains("recentChangesFilters"))
        XCTAssertTrue(source.contains("changeFilter(L10n.text(.storageChangesRange))"))
        XCTAssertTrue(source.contains("changeFilter(L10n.text(.storageChangesType))"))
        XCTAssertTrue(source.contains("changeFilter(L10n.text(.storageChangesSafety))"))
        XCTAssertTrue(source.contains("accessibilityIdentifier(\"storage-mode-picker\")"))
    }

    func testStorageTableColumnsUseNativeAscendingDescendingSortOrder() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("value: \\.storageDisplayName"))
        XCTAssertTrue(source.contains("value: \\.storageParentPath"))
        XCTAssertTrue(source.contains("value: \\.risk"))
        XCTAssertTrue(source.contains("value: \\.allocatedSize"))
        XCTAssertTrue(source.contains("value: \\.storageKindSortValue"))
        XCTAssertTrue(source.contains("value: \\.observedAt"))
        XCTAssertTrue(source.contains("value: \\.magnitudeBytes"))
        XCTAssertTrue(source.contains("ForEach(visibleItems)"))
        XCTAssertTrue(source.contains("ForEach(visibleChanges)"))
    }

    func testStorageWorkbenchFitsTheMinimumSupportedWindowWidth() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("private static let categoryColumnWidth: CGFloat = 260"))
        XCTAssertTrue(source.contains(
            ".frame(width: Self.categoryColumnWidth)"
        ))
        XCTAssertTrue(source.contains(".frame(minWidth: 0)"))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains(".width(min: 120, ideal: 180)"))
        XCTAssertTrue(source.contains(".width(min: 80, ideal: 95)"))
        XCTAssertFalse(source.contains("minWidth: 620"))
        XCTAssertFalse(source.contains(".frame(width: 260)"))
    }

    private func storageViewSource() throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/Views/Storage/StorageView.swift"
            ),
            encoding: .utf8
        )
    }

    private func storageCapacitySource() throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/Views/Storage/StorageCapacityOverview.swift"
            ),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
