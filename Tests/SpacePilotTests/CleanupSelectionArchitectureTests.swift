import Foundation
import XCTest

final class CleanupSelectionArchitectureTests: XCTestCase {
    func testPreparedCleanupUsesExplicitSelectedIDs() throws {
        let model = try source(at: "Sources/SpacePilot/App/AppModel.swift")

        XCTAssertTrue(model.contains(
            "func executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool)"
        ))
        XCTAssertTrue(model.contains("selectedIDs: eligibleSelectedIDs"))
        XCTAssertFalse(model.contains("selectedIDs: Set(cleanupCandidates.map(\\.id))"))
    }

    func testCleanupConfirmationStartsWithSelectionModelAndDisablesEmptyConfirm() throws {
        let view = try source(
            at: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift"
        )

        XCTAssertTrue(view.contains("@State private var selection: CleanupSelection"))
        XCTAssertTrue(view.contains("selection.selectedIDs.isEmpty"))
        XCTAssertTrue(view.contains("selection.toggle(item.id)"))
        XCTAssertTrue(view.contains("onConfirm(selection.selectedIDs, confirmsSensitive)"))
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
