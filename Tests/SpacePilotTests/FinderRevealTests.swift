import AppKit
import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class FinderRevealTests: XCTestCase {
    func testPluginTableLayoutUsesCompactColumnsBelowBreakpoint() {
        XCTAssertEqual(PluginTableLayoutMode(availableWidth: 519), .compact)
        XCTAssertEqual(PluginTableLayoutMode(availableWidth: 619), .compact)
        XCTAssertEqual(PluginTableLayoutMode(availableWidth: 620), .regular)
    }

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
        XCTAssertTrue(detail.contains("GeometryReader { geometry in"))
        XCTAssertTrue(detail.contains("PluginTableLayoutMode(availableWidth: geometry.size.width)"))
        XCTAssertTrue(detail.contains("private var compactPluginTable"))
        XCTAssertTrue(detail.contains("private var regularPluginTable"))
    }

    func testSelectableSurfacesUseNativeTableDoubleActionWithoutCellGestures() throws {
        let adapter = try source(
            at: "Sources/SpacePilot/Views/Shared/NativeTableDoubleClick.swift"
        )
        let applications = try source(
            at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift"
        )
        let developerAI = try source(
            at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift"
        )
        let detail = try source(
            at: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift"
        )
        let storage = try source(
            at: "Sources/SpacePilot/Views/Storage/StorageView.swift"
        )

        XCTAssertTrue(adapter.contains("NSTableView"))
        XCTAssertTrue(adapter.contains("doubleAction = #selector(tableDoubleAction(_:))"))
        XCTAssertTrue(adapter.contains("let row = sender.clickedRow"))
        XCTAssertTrue(adapter.contains("NSApp.sendAction(action, to: previousTarget"))
        XCTAssertTrue(applications.contains("List(applications, selection: $selection)"))
        XCTAssertTrue(applications.contains("List(visibleAssociations, selection: $selectedAssociationID)"))
        XCTAssertTrue(developerAI.contains("selection: $model.selectedAIApplicationID"))
        XCTAssertTrue(storage.contains("selection: $selectedItemIDs"))
        XCTAssertTrue(detail.contains("Table(dataItems, selection: $selectedDataItemID)"))
        XCTAssertTrue(detail.contains("Table(skills, selection: $selectedSkillID)"))
        XCTAssertEqual(
            detail.components(separatedBy: "selection: $selectedPluginID").count - 1,
            2
        )
        XCTAssertFalse(developerAI.contains(".onDoubleClickRevealInFinder("))
        XCTAssertEqual(
            applications.components(separatedBy: ".onDoubleClickRevealInFinder(").count - 1,
            1
        )
        XCTAssertEqual(
            detail.components(separatedBy: ".onDoubleClickRevealInFinder(").count - 1,
            1
        )
        XCTAssertEqual(
            storage.components(separatedBy: ".onDoubleClickRevealInFinder(").count - 1,
            1
        )
    }

    func testCompactPluginTableOnlyDeclaresCoreColumns() throws {
        let source = try source(
            at: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift"
        )
        let compactStart = try XCTUnwrap(source.range(of: "private var compactPluginTable"))
        let regularStart = try XCTUnwrap(source.range(of: "private var regularPluginTable"))
        let compactSource = String(source[compactStart.lowerBound..<regularStart.lowerBound])

        XCTAssertTrue(compactSource.contains("TableColumn(L10n.text(.plugin))"))
        XCTAssertTrue(compactSource.contains("TableColumn(L10n.space())"))
        XCTAssertFalse(compactSource.contains("TableColumn(L10n.version())"))
        XCTAssertFalse(compactSource.contains("TableColumn(L10n.skills())"))
        XCTAssertFalse(compactSource.contains("TableColumn(L10n.management())"))
    }

    func testEveryFileBackedSurfaceUsesSharedDoubleClickHelper() throws {
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/Shared/StorageItemRow.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/Storage/StorageView.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift")
        try assertOccurrences(0, in: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        try assertOccurrences(1, in: "Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift")
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

@MainActor
final class NativeTableDoubleClickCoordinatorTests: XCTestCase {
    func testAttachForwardsActionsRevealsClickedRowAndRestoresLifecycle() {
        _ = NSApplication.shared
        let originalTarget = TableActionTarget()
        let tableView = ClickedRowTableView()
        tableView.target = originalTarget
        tableView.action = #selector(TableActionTarget.singleAction(_:))
        tableView.doubleAction = #selector(TableActionTarget.doubleAction(_:))
        tableView.simulatedClickedRow = 0
        let expectedURL = URL(fileURLWithPath: "/tmp/plugin")
        var revealedURLs: [URL] = []
        let coordinator = NativeTableDoubleClickAdapter.Coordinator(
            urlAtRow: { $0 == 0 ? expectedURL : nil },
            reveal: { revealedURLs.append($0) }
        )

        coordinator.attach(to: tableView)

        XCTAssertTrue(tableView.target === coordinator)
        XCTAssertEqual(tableView.action, #selector(coordinator.tableAction(_:)))
        XCTAssertEqual(tableView.doubleAction, #selector(coordinator.tableDoubleAction(_:)))
        XCTAssertTrue(coordinator.previousTargetForTesting === originalTarget)
        coordinator.tableAction(tableView)
        coordinator.tableDoubleAction(tableView)
        XCTAssertEqual(originalTarget.singleActionCount, 1)
        XCTAssertEqual(originalTarget.doubleActionCount, 1)
        XCTAssertEqual(revealedURLs, [expectedURL])

        coordinator.uninstall()

        XCTAssertTrue(tableView.target === originalTarget)
        XCTAssertEqual(tableView.action, #selector(TableActionTarget.singleAction(_:)))
        XCTAssertEqual(tableView.doubleAction, #selector(TableActionTarget.doubleAction(_:)))
        assertCoordinatorIsCleared(coordinator)
    }

    func testUninstallDoesNotOverwriteLaterTargetAndAlwaysClearsState() {
        let originalTarget = TableActionTarget()
        let laterTarget = TableActionTarget()
        let tableView = NSTableView()
        tableView.target = originalTarget
        tableView.action = #selector(TableActionTarget.singleAction(_:))
        tableView.doubleAction = #selector(TableActionTarget.doubleAction(_:))
        let coordinator = NativeTableDoubleClickAdapter.Coordinator(
            urlAtRow: { _ in nil }
        )
        coordinator.attach(to: tableView)

        tableView.target = laterTarget
        tableView.action = #selector(TableActionTarget.laterSingleAction(_:))
        tableView.doubleAction = #selector(TableActionTarget.laterDoubleAction(_:))
        coordinator.uninstall()

        XCTAssertTrue(tableView.target === laterTarget)
        XCTAssertEqual(tableView.action, #selector(TableActionTarget.laterSingleAction(_:)))
        XCTAssertEqual(
            tableView.doubleAction,
            #selector(TableActionTarget.laterDoubleAction(_:))
        )
        assertCoordinatorIsCleared(coordinator)
    }

    func testRepeatedAttachAndTableSwitchRestoreOnlyTheOwnedTable() {
        let firstTarget = TableActionTarget()
        let secondTarget = TableActionTarget()
        let firstTable = NSTableView()
        let secondTable = NSTableView()
        configure(firstTable, target: firstTarget)
        configure(secondTable, target: secondTarget)
        let coordinator = NativeTableDoubleClickAdapter.Coordinator(
            urlAtRow: { _ in nil }
        )

        coordinator.attach(to: firstTable)
        coordinator.attach(to: firstTable)
        XCTAssertTrue(coordinator.previousTargetForTesting === firstTarget)

        coordinator.attach(to: secondTable)
        XCTAssertTrue(firstTable.target === firstTarget)
        XCTAssertEqual(firstTable.action, #selector(TableActionTarget.singleAction(_:)))
        XCTAssertEqual(
            firstTable.doubleAction,
            #selector(TableActionTarget.doubleAction(_:))
        )
        XCTAssertTrue(secondTable.target === coordinator)
        XCTAssertTrue(coordinator.previousTargetForTesting === secondTarget)

        coordinator.uninstall()
        XCTAssertTrue(secondTable.target === secondTarget)
        assertCoordinatorIsCleared(coordinator)
    }

    private func configure(_ tableView: NSTableView, target: TableActionTarget) {
        tableView.target = target
        tableView.action = #selector(TableActionTarget.singleAction(_:))
        tableView.doubleAction = #selector(TableActionTarget.doubleAction(_:))
    }

    private func assertCoordinatorIsCleared(
        _ coordinator: NativeTableDoubleClickAdapter.Coordinator,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNil(coordinator.attachedTableViewForTesting, file: file, line: line)
        XCTAssertNil(coordinator.previousTargetForTesting, file: file, line: line)
        XCTAssertNil(coordinator.previousActionForTesting, file: file, line: line)
        XCTAssertNil(coordinator.previousDoubleActionForTesting, file: file, line: line)
    }
}

private final class ClickedRowTableView: NSTableView {
    var simulatedClickedRow = -1

    override var clickedRow: Int { simulatedClickedRow }
}

private final class TableActionTarget: NSObject {
    var singleActionCount = 0
    var doubleActionCount = 0

    @objc func singleAction(_ sender: NSTableView) {
        singleActionCount += 1
    }

    @objc func doubleAction(_ sender: NSTableView) {
        doubleActionCount += 1
    }

    @objc func laterSingleAction(_ sender: NSTableView) {}
    @objc func laterDoubleAction(_ sender: NSTableView) {}
}
