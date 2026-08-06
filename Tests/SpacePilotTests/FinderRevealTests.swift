import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class FinderRevealTests: XCTestCase {
    func testAIApplicationUsesApplicationURLBeforeStorageRoot() {
        let applicationURL = URL(fileURLWithPath: "/Applications/Example.app")
        let rootURL = URL(fileURLWithPath: "/Users/test/.example")

        XCTAssertEqual(
            FinderReveal.applicationURL(for: application(
                applicationURL: applicationURL,
                rootURLs: [rootURL]
            )),
            applicationURL
        )
    }

    func testAIApplicationFallsBackToFirstStorageRoot() {
        let firstRoot = URL(fileURLWithPath: "/Users/test/.example")
        let secondRoot = URL(fileURLWithPath: "/Users/test/Library/Example")

        XCTAssertEqual(
            FinderReveal.applicationURL(for: application(
                applicationURL: nil,
                rootURLs: [firstRoot, secondRoot]
            )),
            firstRoot
        )
    }

    func testAIApplicationWithoutKnownURLCannotBeRevealed() {
        XCTAssertNil(FinderReveal.applicationURL(for: application(
            applicationURL: nil,
            rootURLs: []
        )))
    }

    func testCleanupHistoryPrefersExistingResultingURL() {
        let resultingURL = URL(fileURLWithPath: "/Users/test/.Trash/item")
        let sourceURL = URL(fileURLWithPath: "/Users/test/item")

        XCTAssertEqual(
            FinderReveal.cleanupHistoryURL(
                resultingURL: resultingURL,
                sourceURL: sourceURL,
                fileExists: { $0 == resultingURL.path || $0 == sourceURL.path }
            ),
            resultingURL
        )
    }

    func testCleanupHistoryFallsBackToExistingSourceURL() {
        let resultingURL = URL(fileURLWithPath: "/Users/test/.Trash/item")
        let sourceURL = URL(fileURLWithPath: "/Users/test/item")

        XCTAssertEqual(
            FinderReveal.cleanupHistoryURL(
                resultingURL: resultingURL,
                sourceURL: sourceURL,
                fileExists: { $0 == sourceURL.path }
            ),
            sourceURL
        )
    }

    func testCleanupHistoryWithoutExistingURLCannotBeRevealed() {
        XCTAssertNil(FinderReveal.cleanupHistoryURL(
            resultingURL: URL(fileURLWithPath: "/missing/result"),
            sourceURL: URL(fileURLWithPath: "/missing/source"),
            fileExists: { _ in false }
        ))
        XCTAssertNil(FinderReveal.cleanupHistoryURL(
            resultingURL: nil,
            sourceURL: nil,
            fileExists: { _ in true }
        ))
    }

    private func application(
        applicationURL: URL?,
        rootURLs: [URL]
    ) -> AIApplicationRecord {
        AIApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.app",
            applicationURL: applicationURL,
            rootURLs: rootURLs,
            itemIDs: [],
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .basic
        )
    }
}

final class FinderRevealArchitectureTests: XCTestCase {
    func testSharedHelperUsesFinderSelectionAndDoubleClick() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Shared/FinderReveal.swift")

        XCTAssertTrue(source.contains("activateFileViewerSelecting([url])"))
        XCTAssertTrue(source.contains("simultaneousGesture("))
        XCTAssertTrue(source.contains("TapGesture(count: 2)"))
        XCTAssertFalse(source.contains(".onTapGesture(count: 2)"))
        XCTAssertTrue(source.contains("func onDoubleClickRevealInFinder(_ url: URL?)"))
    }

    func testDeveloperAITablesConstrainLongContentAndPluginColumns() throws {
        let detail = try source(
            at: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift"
        )
        let workspace = try source(
            at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift"
        )

        XCTAssertGreaterThanOrEqual(
            detail.components(separatedBy: ".lineLimit(1)").count - 1,
            9
        )
        XCTAssertTrue(detail.contains(".truncationMode(.middle)"))
        XCTAssertTrue(detail.contains(".truncationMode(.tail)"))
        XCTAssertTrue(detail.contains(".width(min: 64, ideal: 76, max: 88)"))
        XCTAssertTrue(detail.contains(".width(min: 52, ideal: 64, max: 76)"))
        XCTAssertTrue(detail.contains(".width(min: 88, ideal: 110, max: 124)"))
        XCTAssertTrue(detail.contains(".width(min: 76, ideal: 92, max: 104)"))
        XCTAssertTrue(workspace.contains(".frame(minWidth: 520, maxWidth: .infinity"))
    }

    func testEveryFileBackedSurfaceUsesSharedDoubleClickHelper() throws {
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/Shared/StorageItemRow.swift")
        try assertOccurrences(3, in: "Sources/SpacePilot/Views/Storage/StorageView.swift")
        try assertOccurrences(3, in: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        try assertOccurrences(4, in: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/History/CleanupHistoryView.swift")
        try assertOccurrences(2, in: "Sources/SpacePilot/Views/Shared/InspectorDetailView.swift")
    }

    func testFallbackHelpersAreUsedAtAIDisplayAndHistorySurfaces() throws {
        let aiList = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        let aiDetail = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift")
        let history = try source(at: "Sources/SpacePilot/Views/History/CleanupHistoryView.swift")

        XCTAssertTrue(aiList.contains("FinderReveal.applicationURL("))
        XCTAssertTrue(aiDetail.contains("FinderReveal.applicationURL(for: application)"))
        XCTAssertTrue(history.contains("FinderReveal.cleanupHistoryURL("))
        XCTAssertTrue(history.contains("resultingURL: outcome.resultingURL"))
        XCTAssertTrue(history.contains("sourceURL: outcome.sourceURL"))
    }

    func testCleanupCheckboxAndRevealContentAreSiblingViews() throws {
        let source = try source(
            at: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift"
        )

        XCTAssertTrue(source.contains("Toggle(\"\", isOn: binding(for: reviewItem))"))
        XCTAssertTrue(source.contains(".labelsHidden()"))
        XCTAssertTrue(source.contains("HStack(alignment: .top, spacing: 8) {"))
        XCTAssertFalse(source.contains("Toggle(isOn: binding(for: reviewItem)) {"))
        XCTAssertEqual(source.components(separatedBy: "selection.toggle(item.id)").count - 1, 1)
    }

    func testHistoryDisplaysTheSameURLUsedForFinderReveal() throws {
        let source = try source(
            at: "Sources/SpacePilot/Views/History/CleanupHistoryView.swift"
        )

        XCTAssertTrue(source.contains("let revealURL = FinderReveal.cleanupHistoryURL("))
        XCTAssertTrue(source.contains("let displayURL = revealURL"))
        XCTAssertTrue(source.contains(".onDoubleClickRevealInFinder(revealURL)"))
    }

    private func assertOccurrences(_ expected: Int, in relativePath: String) throws {
        let source = try source(at: relativePath)
        XCTAssertEqual(
            source.components(separatedBy: ".onDoubleClickRevealInFinder(").count - 1,
            expected,
            relativePath
        )
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
