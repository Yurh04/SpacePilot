import Foundation
import XCTest

final class OverviewChartArchitectureTests: XCTestCase {
    func testOverviewComposesBothNativeChartsResponsively() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")

        XCTAssertTrue(source.contains("DiskCapacityChart("))
        XCTAssertTrue(source.contains("AnalyzedCategoryChart("))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertTrue(source.contains("minWidth: 900"))
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
        XCTAssertTrue(source.contains("overviewDiskCapacityChart"))
        XCTAssertTrue(source.contains("overviewDiskTotal"))
        XCTAssertTrue(source.contains("overviewDiskUsed"))
        XCTAssertTrue(source.contains("overviewDiskAvailable"))
        XCTAssertTrue(source.contains("height: 220"))
    }

    func testDiskSectorsHaveVisibleNonColorLabels() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift")

        XCTAssertTrue(source.contains(".annotation(position: .overlay)"))
        XCTAssertTrue(source.contains("if segment.bytes > 0"))
        XCTAssertTrue(source.contains("Text(verbatim: segment.name)"))
    }

    func testVisibleDiskCopiesAreHiddenBehindOneAccessibilityReplacement() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift")

        XCTAssertTrue(source.contains("visibleCapacityValues"))
        XCTAssertTrue(source.contains("accessibleCapacityValues"))
        XCTAssertTrue(source.contains(".accessibilityHidden(true)"))
        XCTAssertTrue(source.contains(".accessibilityRepresentation"))
    }

    func testAnalyzedCategoryChartUsesAccessibleHorizontalBars() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(source.contains("import Charts"))
        XCTAssertTrue(source.contains("BarMark("))
        XCTAssertTrue(source.contains("x: .value"))
        XCTAssertTrue(source.contains("y: .value"))
        XCTAssertTrue(source.contains("accessibilityRepresentation"))
        XCTAssertTrue(source.contains("height: 220"))
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

    func testRecommendationsRemainAfterTheChartSection() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let chart = try XCTUnwrap(source.range(of: "ViewThatFits(in: .horizontal)"))
        let recommendations = try XCTUnwrap(
            source.range(of: "Section(L10n.text(.overviewSafeRecommendations))")
        )

        XCTAssertLessThan(chart.lowerBound, recommendations.lowerBound)
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
