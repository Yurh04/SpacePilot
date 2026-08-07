import Foundation
import XCTest

final class DeveloperAIArchitectureTests: XCTestCase {
    func testDeveloperAIViewUsesStableSectionListNotSegmentedPicker() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("List(AIManagementSection.allCases, selection: $section)"))
        XCTAssertTrue(source.contains("L10n.aiSectionTitle(for: entry)"))
        // The five-section shell must not reintroduce a horizontal segmented
        // picker at the Developer & AI level (breaks under long zh labels).
        XCTAssertFalse(source.contains(".pickerStyle(.segmented)"))
        // Internal layout uses HSplitView, not a nested NavigationSplitView, to
        // avoid a second sidebar/toolbar and to keep the narrowest width small.
        XCTAssertTrue(source.contains("HSplitView"))
        XCTAssertFalse(source.contains("NavigationSplitView"))
    }

    func testDeveloperAIViewRoutesToEveryReadOnlySection() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("AIManagementOverviewView("))
        XCTAssertTrue(source.contains("AIAppsSectionView("))
        XCTAssertTrue(source.contains("GlobalSkillsView("))
        XCTAssertTrue(source.contains("GlobalPluginsView("))
        XCTAssertTrue(source.contains("CLIToolsView("))
    }

    func testDeveloperAIViewJoinsRegistryApplicationsWithoutDisplayNameGuessing() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("AIApplicationJoin.registryOnlyApplications("))
    }

    func testAIAppsSectionUsesNativeDoubleClickAndKeepsSelectionAligned() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAppsSectionView.swift")

        XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal"))
        // A single flat List with unified selection; no Section/header rows that
        // would break the clickedRow -> entries[row] mapping.
        XCTAssertTrue(source.contains("List(entries, selection: $selectedEntryID)"))
        XCTAssertFalse(source.contains("Section("))
        // The unified selection is synced back to the model's deep selection.
        XCTAssertTrue(source.contains("model.selectedAIApplicationID = deepID"))
        // Selectable rows must not re-add a competing SwiftUI double-tap gesture
        // or a per-row single-tap gesture.
        XCTAssertFalse(source.contains("TapGesture(count: 2)"))
        XCTAssertFalse(source.contains(".simultaneousGesture("))
        XCTAssertFalse(source.contains("onDoubleClickRevealInFinder"))
    }

    func testAIAppsSidebarEntriesFlattenBothKindsForRowMapping() throws {
        let source = try source(
            at: "Sources/SpacePilotCore/AI/Discovery/AIAppsSidebarEntry.swift"
        )

        XCTAssertTrue(source.contains("case deep(deepID: UUID)"))
        XCTAssertTrue(source.contains("case registry(registryID: String)"))
        XCTAssertTrue(source.contains("let revealURL: URL?"))
    }

    func testGlobalSkillsAndPluginsUseCompactAndRegularLayoutBranches() throws {
        let skills = try source(at: "Sources/SpacePilot/Views/DeveloperAI/GlobalSkillsView.swift")
        let plugins = try source(at: "Sources/SpacePilot/Views/DeveloperAI/GlobalPluginsView.swift")

        for source in [skills, plugins] {
            XCTAssertTrue(source.contains("GeometryReader"))
            XCTAssertTrue(source.contains("PluginTableLayoutMode(availableWidth: geometry.size.width)"))
            XCTAssertTrue(source.contains("layout == .compact"))
            XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal(urlAtRow:"))
            XCTAssertTrue(source.contains(".truncationMode("))
            XCTAssertTrue(source.contains("AISectionFilter."))
        }
    }

    func testCLIToolsViewShowsHonestCoverageStatusAndRevealsExecutable() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")

        XCTAssertTrue(source.contains("let clis: [AIToolRecord]"))
        XCTAssertTrue(source.contains("tool.coverageFailures"))
        XCTAssertTrue(source.contains("evidence.executableURL"))
        XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal(urlAtRow:"))
        XCTAssertTrue(source.contains("PluginTableLayoutMode(availableWidth: geometry.size.width)"))
    }

    func testDeveloperAIViewFeedsCLIToolsFromManagementProjection() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("clis: model.aiManagementProjection.clis"))
    }

    func testDeveloperAIShellOwnsPerSectionSelectionBindings() throws {
        // Selection state must live in the persistent shell so switching the
        // section (which destroys/recreates the conditional subtrees) does not
        // reset each page's selection.
        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains("@State private var selectedAIEntryID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedSkillID: UUID?"))
        XCTAssertTrue(shell.contains("@State private var selectedPluginID: UUID?"))
        XCTAssertTrue(shell.contains("@State private var selectedCLIID: String?"))
        // The shell passes each selection down as a binding.
        XCTAssertTrue(shell.contains("selectedEntryID: $selectedAIEntryID"))
        XCTAssertTrue(shell.contains("selection: $selectedSkillID"))
        XCTAssertTrue(shell.contains("selection: $selectedPluginID"))
        XCTAssertTrue(shell.contains("selection: $selectedCLIID"))

        // The subviews must consume the selection as a @Binding and must not
        // declare their own @State selection that would be reset on rebuild.
        let apps = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAppsSectionView.swift")
        XCTAssertTrue(apps.contains("@Binding var selectedEntryID: String?"))
        XCTAssertFalse(apps.contains("@State private var selectedEntryID"))

        for page in [
            "Sources/SpacePilot/Views/DeveloperAI/GlobalSkillsView.swift",
            "Sources/SpacePilot/Views/DeveloperAI/GlobalPluginsView.swift",
            "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift",
        ] {
            let source = try source(at: page)
            XCTAssertTrue(source.contains("@Binding var selection:"))
            XCTAssertFalse(source.contains("@State private var selection"))
        }
    }

    func testDeveloperAIShellRestoresDeepSelectionViaResolver() throws {
        // AI Apps must restore an existing valid deep selection rather than
        // clobbering it with the first row on rebuild.
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAppsSectionView.swift")
        XCTAssertTrue(source.contains("AIAppsSidebar.resolvedSelection("))
    }

    func testAIAppsAndCLIDistinguishDiscoveringAndErrorStates() throws {
        // Empty/refresh states must not be reported as a bare "no data".
        let apps = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAppsSectionView.swift")
        XCTAssertTrue(apps.contains("isDiscovering"))
        XCTAssertTrue(apps.contains("discoveryError"))

        let cli = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")
        XCTAssertTrue(cli.contains("isDiscovering"))
        XCTAssertTrue(cli.contains("discoveryError"))
        // A lightweight refresh banner keeps existing read-only data visible.
        XCTAssertTrue(cli.contains("AIDiscoveryBanner"))
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
