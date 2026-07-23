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
        XCTAssertTrue(source.contains("reviewCleanup(safeSelectedItems)"))
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
