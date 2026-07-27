import Foundation
import XCTest

final class StorageWorkbenchArchitectureTests: XCTestCase {
    func testStorageViewConnectsCategoryAndTableSelection() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("@State private var categorySelection"))
        XCTAssertTrue(source.contains("@State private var selectedItemIDs"))
        XCTAssertTrue(source.contains("projection.items("))
        XCTAssertTrue(source.contains(
            "Table(of: ScannedItem.self, selection: $selectedItemIDs)"
        ))
        XCTAssertTrue(source.contains("safeSelectedItems"))
    }

    func testStorageViewShowsDiskMetricsAndVisibleCleanupAction() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains("projection.totalCapacity"))
        XCTAssertTrue(source.contains("projection.availableBytes"))
        XCTAssertTrue(source.contains("ProgressView("))
        XCTAssertTrue(source.contains(
            "reviewButton(items: safeSelectedItems)"
        ))
    }

    func testStorageWorkbenchFitsTheMinimumSupportedWindowWidth() throws {
        let source = try storageViewSource()

        XCTAssertTrue(source.contains(
            ".frame(minWidth: 190, idealWidth: 220, maxWidth: 250)"
        ))
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

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
