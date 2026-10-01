import Foundation
import XCTest
@testable import SpacePilot
@testable import SpacePilotCore

final class InteractiveHoverCoverageTests: XCTestCase {
    func testEveryClickableViewFileIsInTheAuditInventory() throws {
        let audited: Set<String> = [
            "AppRootView.swift", "SidebarView.swift",
            "Applications/ApplicationsView.swift",
            "DeveloperAI/AIAgentDetailView.swift", "DeveloperAI/AIApplicationDetailView.swift",
            "DeveloperAI/AIManagementOverviewView.swift", "DeveloperAI/AIUpdateActionBar.swift",
            "DeveloperAI/AIUpdateConfirmSheet.swift", "DeveloperAI/CLIToolsView.swift",
            "DeveloperAI/DeveloperAIView.swift", "DeveloperAI/DiscoveredAIApplicationView.swift",
            "DeveloperAI/GlobalPluginsView.swift", "DeveloperAI/GlobalSkillsView.swift",
            "DeveloperAI/MCPServersView.swift", "DeveloperAI/OtherAIToolsView.swift",
            "DeveloperAI/ProjectApprovalBar.swift", "History/CleanupHistoryView.swift",
            "Overview/OverviewView.swift", "Settings/SettingsView.swift",
            "Shared/CleanupConfirmationView.swift", "Shared/FinderReveal.swift",
            "Shared/InspectorDetailView.swift", "Shared/NativeTableDoubleClick.swift",
            "Shared/StorageItemRow.swift", "Storage/StorageView.swift"
        ]
        let views = repositoryRoot.appending(path: "Sources/SpacePilot/Views")
        let files = try XCTUnwrap(
            FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil)
        ).compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let tokens = ["Button", "NavigationLink", "onTapGesture", "simultaneousGesture",
                      "buttonStyle", "contextMenu", "onDoubleClickRevealInFinder",
                      "nativeTableDoubleClickReveal", "List(", "List {", "Table(",
                      "Picker(", "Toggle(", "Menu("]
        let found = try Set(files.compactMap { file -> String? in
            let contents = try String(contentsOf: file, encoding: .utf8)
            guard tokens.contains(where: contents.contains) else { return nil }
            return String(file.path.dropFirst(views.path.count + 1))
        })
        XCTAssertEqual(found, audited, "Review and classify every newly clickable view file")
    }

    func testTopLevelNativeControlsAndContainersStayUndecorated() throws {
        for path in ["AppRootView.swift", "SidebarView.swift", "Overview/OverviewView.swift"] {
            assertNoHover(try source(path), path: path)
        }
        let overview = try source("Overview/OverviewView.swift")
        XCTAssertTrue(overview.contains("HStack(spacing: 0)"))
        XCTAssertEqual(occurrences(of: "recentChangeMetric(", in: overview), 4)
        XCTAssertTrue(overview.contains("ViewThatFits(in: .horizontal)"))
    }

    func testCustomDoubleClickSurfacesShowHoverOnlyWhenRevealIsAvailable() throws {
        let application = try source("DeveloperAI/AIApplicationDetailView.swift")
        XCTAssertTrue(application.contains(
            ".onDoubleClickRevealInFinder(applicationRevealURL)\n                    .interactiveHover(isEnabled: applicationRevealURL != nil"
        ))
        let discovered = try source("DeveloperAI/DiscoveredAIApplicationView.swift")
        XCTAssertTrue(discovered.contains(
            ".onDoubleClickRevealInFinder(url)\n                    .interactiveHover("
        ))
        let recommendation = try source("Shared/StorageItemRow.swift")
        XCTAssertTrue(recommendation.contains(
            ".onDoubleClickRevealInFinder(item.url)\n        .interactiveHover("
        ))
        let inspector = try source("Shared/InspectorDetailView.swift")
        XCTAssertEqual(occurrences(of: ".interactiveHover(", in: inspector), 2)
        let applications = try source("Applications/ApplicationsView.swift")
        XCTAssertTrue(applications.contains(
            ".onDoubleClickRevealInFinder(application.url)\n                .interactiveHover("
        ))
        let storage = try source("Storage/StorageView.swift")
        XCTAssertTrue(storage.contains(
            ".onDoubleClickRevealInFinder(item.url)\n            .interactiveHover("
        ))
    }

    func testAgentEvidenceRowScopesRevealAndHoverToIdentity() throws {
        let detail = try source("DeveloperAI/AIAgentDetailView.swift")
        let start = try XCTUnwrap(detail.range(of: "private func evidenceRow"))
        let end = try XCTUnwrap(detail.range(of: "// MARK: - Storage module", range: start.lowerBound..<detail.endIndex))
        let row = String(detail[start.lowerBound..<end.lowerBound])

        let identity = try XCTUnwrap(row.range(of: "AIAssetIdentity(name: label, subtitle: path, url: url)"))
        let finderButton = try XCTUnwrap(row.range(of: "Button { FinderReveal.reveal(url) } label:"))
        XCTAssertLessThan(identity.lowerBound, finderButton.lowerBound)
        let identitySurface = row[identity.lowerBound..<finderButton.lowerBound]
        XCTAssertTrue(identitySurface.contains(".onDoubleClickRevealInFinder(url)"))
        XCTAssertTrue(identitySurface.contains(".interactiveHover(cornerRadius: 6)"))
        XCTAssertFalse(row[finderButton.lowerBound...].contains(".onDoubleClickRevealInFinder"))
        XCTAssertFalse(row[finderButton.lowerBound...].contains(".interactiveHover"))
    }

    func testApplicationCollectionsInstallHoverAtBothNativeLists() throws {
        let source = try source("Applications/ApplicationsView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 2)
        XCTAssertTrue(source.contains("applications.indices.contains(row)"))
        XCTAssertTrue(source.contains("rowURLs.indices.contains(row)"))
    }

    func testApplicationPlainSearchClearButtonHasControlHover() throws {
        let source = try source("Applications/ApplicationsView.swift")
        XCTAssertTrue(source.contains(".buttonStyle(.plain)\n                        .interactiveHover(cornerRadius: 6)"))
        XCTAssertEqual(occurrences(of: ".interactiveHover", in: source), 2)
    }

    func testAssociationVisibleRowMapPreservesHeaderSlotsAndCollapsedSearchExpansion() {
        let pairs = [
            associationPair(path: "/tmp/developer", category: .developer),
            associationPair(path: "/tmp/cache", category: .cache)
        ]
        let groups = ApplicationAssociationGroup.grouped(pairs)
        let collapsedRows = ApplicationAssociationGroup.tableRowURLs(
            for: groups, collapsedCategories: [.developer], expandAll: false
        )
        XCTAssertEqual(collapsedRows, [nil, nil, URL(filePath: "/tmp/cache")])

        let searchingRows = ApplicationAssociationGroup.tableRowURLs(
            for: groups, collapsedCategories: [.developer], expandAll: true
        )
        XCTAssertEqual(searchingRows, [
            nil, URL(filePath: "/tmp/developer"), nil, URL(filePath: "/tmp/cache")
        ])
    }

    func testStorageInstallsHoverAtCategoryListAndBothTables() throws {
        let source = try source("Storage/StorageView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 3)
        XCTAssertTrue(source.contains("row > 0 && row <= projection.categories.count + 1"),
            "Category headings and the read-only unattributed row must be excluded")
        XCTAssertTrue(source.contains("visibleItems.indices.contains(row)"))
        XCTAssertTrue(source.contains("visibleChanges.indices.contains(row)"))
    }

    func testCleanupConfirmationUsesVisibleItemsAndSuppressesExecutingRows() throws {
        let source = try source("Shared/CleanupConfirmationView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 1)
        XCTAssertTrue(source.contains("!isExecuting && items.indices.contains(row)"))
    }

    func testHistoryMapsExpandedVisibleRowsAndOnlyRevealableOutcomes() throws {
        let source = try source("History/CleanupHistoryView.swift")
        XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight", in: source), 1)
        XCTAssertTrue(source.contains("expandedTransactionIDs.contains(transaction.id)"))
        XCTAssertTrue(source.contains("hoverRows.indices.contains(row) && hoverRows[row]"))
        XCTAssertTrue(source.contains("FinderReveal.cleanupHistoryURL("))
    }

    func testReadOnlyMetricsCapacityAndSummariesHaveNoHover() throws {
        for (path, marker) in [
            ("Applications/ApplicationsView.swift", "private struct ApplicationMetric:"),
            ("Storage/StorageView.swift", "private struct StorageUnattributedRow:"),
            ("Storage/StorageView.swift", "private struct StorageChangeSummary:")
        ] {
            let content = try source(path)
            let start = try XCTUnwrap(content.range(of: marker)).lowerBound
            let remaining = content[start...]
            let end = remaining.dropFirst(marker.count).range(of: "\nprivate ")?.lowerBound
                ?? content.endIndex
            assertNoHover(String(content[start..<end]), path: path)
        }
        assertNoHover(try source("Storage/StorageCapacityOverview.swift"),
            path: "Storage/StorageCapacityOverview.swift")
    }

    func testDeveloperAINativeCollectionsHaveExplicitVisibleRowPredicates() throws {
        for (file, count) in [("DeveloperAIView", 1), ("AIApplicationDetailView", 4),
                              ("GlobalSkillsView", 3), ("GlobalPluginsView", 3),
                              ("MCPServersView", 2), ("CLIToolsView", 2), ("OtherAIToolsView", 2)] {
            let content = try source("DeveloperAI/\(file).swift")
            XCTAssertEqual(occurrences(of: ".nativeTableHoverHighlight { row in", in: content), count, file)
            XCTAssertFalse(content.contains(".nativeTableHoverHighlight()"), file)
            XCTAssertFalse(content.contains(".onTapGesture"), "\(file): preserve native selection")
        }
        let applicationDetail = try source("DeveloperAI/AIApplicationDetailView.swift")
        let overview = try XCTUnwrap(applicationDetail.range(of: "case .overview:")).lowerBound
        let storage = try XCTUnwrap(applicationDetail.range(of: "case .dataStorage:")).lowerBound
        assertNoHover(String(applicationDetail[overview..<storage]), path: "Application read-only overview")
    }

    private func assertNoHover(_ source: String, path: String) {
        XCTAssertFalse(source.contains(".interactiveHover"), path)
        XCTAssertFalse(source.contains(".nativeTableHoverHighlight"), path)
    }

    private func occurrences(of token: String, in source: String) -> Int {
        source.components(separatedBy: token).count - 1
    }

    private func associationPair(path: String, category: ItemCategory) -> ApplicationAssociationProjection {
        let item = ScannedItem(
            url: URL(filePath: path), logicalSize: 100, allocatedSize: 100,
            category: category, risk: .rebuildable, explanation: "Hover fixture"
        )
        return ApplicationAssociationProjection(
            association: ArtifactAssociation(
                itemID: item.id, applicationID: UUID(), evidence: .knownRule,
                confidence: .high, risk: .rebuildable, ownership: .owned
            ),
            item: item
        )
    }

    private func source(_ path: String) throws -> String {
        return try String(contentsOf: repositoryRoot.appending(path: "Sources/SpacePilot/Views/\(path)"),
            encoding: .utf8)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
