import Foundation
import XCTest

final class OverviewChartArchitectureTests: XCTestCase {
    func testOverviewPlacesSpaceDetailsBesideCleanupWithNarrowFallback() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("primaryWorkspace("))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 12)"))
        XCTAssertEqual(source.components(separatedBy: ".frame(minWidth: 375").count - 1, 2)
        XCTAssertTrue(source.contains(".frame(height: 430)"))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 12)"))
        XCTAssertTrue(source.contains("recentCleanup: state.recentCleanup"))
        XCTAssertTrue(source.contains("if let recentCleanup"))
        XCTAssertTrue(source.contains("cleanupWorkspace("))
        XCTAssertTrue(source.contains("recentCleanupSummary("))
        XCTAssertTrue(source.contains("DiskCapacityChart("))
        XCTAssertTrue(source.contains("AnalyzedCategoryChart("))
        XCTAssertFalse(source.contains("DisclosureGroup"))
        XCTAssertFalse(source.contains("isSpaceDetailsExpanded"))
    }

    func testOverviewOnlyRendersWholeDiskChartWhenCapacityIsProven() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("if projection.hasWholeDiskCapacity"))
        XCTAssertTrue(source.contains("overviewDiskCapacityUnavailableDescription"))
    }

    func testDiskCapacityChartUsesAnAccessibleNativeDonut() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift")

        XCTAssertTrue(source.contains("import Charts"))
        XCTAssertTrue(source.contains("SectorMark("))
        XCTAssertTrue(source.contains(".chartLegend(.hidden)"))
        XCTAssertTrue(source.contains(".frame(width: 132, height: 132)"))
        XCTAssertTrue(source.contains("overviewDiskCapacityChart"))
        XCTAssertTrue(source.contains("overviewDiskTotal"))
        XCTAssertTrue(source.contains("overviewDiskUsed"))
        XCTAssertTrue(source.contains("overviewDiskAvailable"))
    }

    func testDiskCapacityChartPairsTheDonutWithDirectValues() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift")

        XCTAssertTrue(source.contains("Text(ByteCount.string(availableBytes))"))
        XCTAssertTrue(source.contains("visibleCapacityValues"))
        XCTAssertTrue(source.contains("capacityValue("))
        XCTAssertTrue(source.contains(".font(.subheadline.weight(.semibold))"))
        XCTAssertTrue(source.contains(".monospacedDigit()"))
    }

    func testVisibleDiskCopiesAreHiddenBehindOneAccessibilityReplacement() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift")

        XCTAssertTrue(source.contains("visibleCapacityValues"))
        XCTAssertTrue(source.contains("accessibleCapacityValues"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(source.contains(".accessibilityRepresentation"))
    }

    func testAnalyzedCategoryChartUsesReadableDirectLabelsAndProportionalBars() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(source.contains("maxVisibleCategories = 5"))
        XCTAssertTrue(source.contains("GeometryReader"))
        XCTAssertTrue(source.contains("Capsule()"))
        XCTAssertTrue(source.contains("StorageCategoryAppearance.color"))
        XCTAssertTrue(source.contains("StorageCategoryAppearance.symbol"))
        XCTAssertTrue(source.contains(".font(.body.weight(.medium))"))
        XCTAssertTrue(source.contains(".font(.body.weight(.semibold))"))
        XCTAssertTrue(source.contains("Self.sizeLabel(for: bytes)"))
        XCTAssertTrue(source.contains("storageOtherAnalyzed"))
        XCTAssertTrue(source.contains("accessibilityRepresentation"))
    }

    func testAnalyzedCategoryChartHasACompactLocalizedEmptyState() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(source.contains("if categories.isEmpty"))
        XCTAssertTrue(source.contains("overviewAnalyzedCategoriesEmpty"))
        XCTAssertTrue(source.contains("chart.bar.xaxis"))
    }

    func testProjectionFiltersZeroByteCategoriesIntoTheCompactEmptyState() throws {
        let projection = try source(at: "Sources/SpacePilotCore/Models/ViewProjections.swift")
        let overview = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let chart = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(projection.contains("guard total.allocatedSize > 0 else"))
        XCTAssertTrue(overview.contains("AnalyzedCategoryChart(categories: projection.categories)"))
        XCTAssertTrue(chart.contains("if categories.isEmpty"))
    }

    func testVisibleCategoryCopiesAreHiddenBehindOneAccessibilityReplacement() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(source.contains(".accessibilityRepresentation"))
    }

    func testOverviewKeepsThePrimaryViewportCompact() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("LazyVStack(alignment: .leading, spacing: 12)"))
        XCTAssertTrue(source.contains("recommendationPreviewLimit("))
        XCTAssertTrue(source.contains(".prefix(previewLimit)"))
        XCTAssertTrue(source.contains("minHeight: 28"))
        XCTAssertTrue(source.contains("GridItem(.flexible(), spacing: 8)"))
        XCTAssertTrue(source.contains("GroupBox"))
        XCTAssertTrue(source.contains(".contentTransition(.numericText())"))
    }

    func testOverviewIncludesARecentChangesQuickAction() throws {
        let overview = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let root = try source(at: "Sources/SpacePilot/Views/AppRootView.swift")

        XCTAssertTrue(overview.contains("overviewViewRecentChanges"))
        XCTAssertTrue(overview.contains("clock.arrow.circlepath"))
        XCTAssertTrue(overview.contains("action: openRecentChanges"))
        XCTAssertTrue(root.contains("model.storageItemMode = .recent"))
        XCTAssertTrue(root.contains("mode: $model.storageItemMode"))
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
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
