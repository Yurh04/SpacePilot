import Foundation
import XCTest

final class OverviewChartArchitectureTests: XCTestCase {
    func testOverviewSeparatesSummaryAndInsightsWithNarrowFallback() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("primaryWorkspace("))
        XCTAssertTrue(source.contains("summaryWorkspace("))
        XCTAssertTrue(source.contains("insightsWorkspace("))
        XCTAssertTrue(source.contains("quickLookActions("))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 16)"))
        XCTAssertEqual(
            source.components(separatedBy: "minWidth: 360,").count - 1,
            2
        )
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 16)"))
        let workspaceStart = try XCTUnwrap(source.range(of: "private func primaryWorkspace"))
        let workspaceEnd = try XCTUnwrap(
            source.range(of: "private func recentChangesSummary", range: workspaceStart.upperBound..<source.endIndex)
        )
        let workspace = String(source[workspaceStart.lowerBound..<workspaceEnd.lowerBound])
        XCTAssertGreaterThanOrEqual(
            workspace.components(separatedBy: "maxHeight: .infinity").count - 1,
            3
        )
        XCTAssertTrue(workspace.contains(".fixedSize(horizontal: false, vertical: true)"))
        XCTAssertTrue(source.contains("recentCleanup: state.recentCleanup"))
        XCTAssertTrue(source.contains("if let recentCleanup"))
        XCTAssertTrue(source.contains("recentCleanupSummary("))
        XCTAssertTrue(source.contains("L10n.text(.overviewSpaceDetails)"))
        XCTAssertTrue(source.contains("DiskCapacityChart("))
        XCTAssertTrue(source.contains("AnalyzedCategoryChart("))
        XCTAssertFalse(source.contains("DisclosureGroup"))
        XCTAssertFalse(source.contains("isSpaceDetailsExpanded"))
    }

    func testOverviewSplitsTheLeftColumnIntoThreeIndependentCards() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("cleanupRecommendationsCard("))
        XCTAssertTrue(source.contains("recentChangesCard("))
        XCTAssertTrue(source.contains("recentCleanupCard("))
        XCTAssertTrue(source.contains("VStack(alignment: .leading, spacing: 12)"))
    }

    func testQuickActionsShareAResponsiveTopRowWithTheCompactCoverageWarning() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let dashboardStart = try XCTUnwrap(source.range(of: "private func dashboard"))
        let dashboardEnd = try XCTUnwrap(
            source.range(of: "private func storageStatus", range: dashboardStart.upperBound..<source.endIndex)
        )
        let dashboard = String(source[dashboardStart.lowerBound..<dashboardEnd.lowerBound])
        XCTAssertTrue(dashboard.contains("topActionRow(projection)"))

        let rowStart = try XCTUnwrap(source.range(of: "private func topActionRow"))
        let rowEnd = try XCTUnwrap(
            source.range(of: "private func quickLookActions", range: rowStart.upperBound..<source.endIndex)
        )
        let row = String(source[rowStart.lowerBound..<rowEnd.lowerBound])
        XCTAssertTrue(row.contains("HStack(alignment: .center, spacing: 12)"))
        XCTAssertTrue(row.contains("quickLookActions()"))
        XCTAssertTrue(row.contains("coverageWarning(projection)"))
        XCTAssertTrue(row.contains(".frame(minWidth: 620, maxWidth: .infinity)"))
        XCTAssertTrue(row.contains("VStack(alignment: .leading, spacing: 12)"))
        XCTAssertTrue(source.contains(".fixedSize(horizontal: true, vertical: false)"))
        XCTAssertTrue(source.contains(".controlSize(.small)"))
        XCTAssertTrue(source.contains(".help(L10n.text(.overviewLimitedCoverageDescription))"))
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

        XCTAssertTrue(source.contains("LazyVStack(alignment: .leading, spacing: 16)"))
        XCTAssertTrue(source.contains("recommendationPreviewLimit("))
        XCTAssertTrue(source.contains(".prefix(previewLimit)"))
        XCTAssertTrue(source.contains("GridItem(.flexible(), spacing: 10)"))
        XCTAssertTrue(source.contains("GroupBox"))
        XCTAssertTrue(source.contains(".contentTransition(.numericText())"))
    }

    func testRecentChangesRemainAHorizontalSummary() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let start = try XCTUnwrap(source.range(of: "private func recentChangesSummary"))
        let end = try XCTUnwrap(
            source.range(of: "private func recommendationPreviewLimit", range: start.upperBound..<source.endIndex)
        )
        let summary = String(source[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(summary.contains("HStack(spacing: 0)"))
        XCTAssertEqual(summary.components(separatedBy: "recentChangeMetric(").count - 1, 3)
        XCTAssertFalse(summary.contains("VStack(alignment: .leading, spacing: 12)"))
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

    func testOverviewIncludesAnInstallerQuickAction() throws {
        let overview = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let root = try source(at: "Sources/SpacePilot/Views/AppRootView.swift")

        XCTAssertTrue(overview.contains("overviewViewInstallers"))
        XCTAssertTrue(overview.contains("shippingbox.and.arrow.backward.fill"))
        XCTAssertTrue(overview.contains("action: openInstallers"))
        XCTAssertTrue(root.contains("model.storageItemMode = .largest"))
        XCTAssertTrue(root.contains("model.storageCategorySelection = .category(.installer)"))
        XCTAssertTrue(root.contains("categorySelection: $model.storageCategorySelection"))
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
