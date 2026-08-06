import Foundation
import XCTest

final class DeveloperAIArchitectureTests: XCTestCase {
    func testDeveloperAIViewKeepsSelectionAlignedWithAvailableApplications() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains(".onChange(of: projection.applications.map(\\.id), initial: true)"))
        XCTAssertTrue(source.contains("model.selectedAIApplicationID = applicationIDs.first"))
        XCTAssertFalse(source.contains(".onAppear {"))
    }

    func testDeveloperAIViewUsesDedicatedEmptyStateWhenNoApplicationsAreIndexed() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("if projection.applications.isEmpty"))
        XCTAssertTrue(source.contains("ContentUnavailableView("))
        XCTAssertTrue(source.contains("L10n.developerAI()"))
        XCTAssertTrue(source.contains("Text(verbatim: L10n.noData())"))
        XCTAssertTrue(source.contains("L10n.text(.aiSelectApplication)"))
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
