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

    func testAnalyzedCategoryChartUsesAccessibleHorizontalBars() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift")

        XCTAssertTrue(source.contains("import Charts"))
        XCTAssertTrue(source.contains("BarMark("))
        XCTAssertTrue(source.contains("x: .value"))
        XCTAssertTrue(source.contains("y: .value"))
        XCTAssertTrue(source.contains("accessibilityRepresentation"))
        XCTAssertTrue(source.contains("height: 220"))
    }

    func testRecommendationsRemainAfterTheChartSection() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Overview/OverviewView.swift")
        let chart = try XCTUnwrap(source.range(of: "DiskCapacityChart("))
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
