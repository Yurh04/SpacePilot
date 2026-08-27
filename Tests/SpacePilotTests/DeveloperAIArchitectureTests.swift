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
        XCTAssertTrue(source.contains("AIAgentsSectionView("))
        XCTAssertTrue(source.contains("GlobalSkillsView("))
        XCTAssertTrue(source.contains("GlobalPluginsView("))
        XCTAssertTrue(source.contains("CLIToolsView("))
    }

    func testDeveloperAIViewBuildsAgentProjectionByDefinitionNotDisplayName() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        // Agents are unified from discovered records via the Core projection,
        // which joins by stable definitionID (never by display name).
        XCTAssertTrue(source.contains("AIAgentProjection(records: model.aiManagementProjection.records)"))
        XCTAssertFalse(source.contains("AIApplicationJoin.registryOnlyApplications("))
    }

    func testAIAgentsSectionUsesTwoNativeDoubleClickListsSplitByLocality() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentsSectionView.swift")

        XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal"))
        // Two flat lists (local top, remote bottom) each keyed to the shared
        // String selection; no `Section(` header rows that would break the
        // clickedRow -> entries[row] mapping inside a list.
        XCTAssertTrue(source.contains("List(localAgents, selection: $selectedEntryID)"))
        XCTAssertTrue(source.contains("List(remoteAgents, selection: $selectedEntryID)"))
        XCTAssertFalse(source.contains("Section("))
        // Local agents are shown above remote agents.
        let localRange = try XCTUnwrap(source.range(of: "private var localSection"))
        let remoteRange = try XCTUnwrap(source.range(of: "private var remoteSection"))
        XCTAssertTrue(localRange.lowerBound < remoteRange.lowerBound)
        // Selectable rows must not re-add a competing SwiftUI double-tap gesture
        // or a per-row single-tap gesture.
        XCTAssertFalse(source.contains("TapGesture(count: 2)"))
        XCTAssertFalse(source.contains(".simultaneousGesture("))
        XCTAssertFalse(source.contains(".onTapGesture"))
        XCTAssertFalse(source.contains("onDoubleClickRevealInFinder"))
    }

    func testAIAgentDetailRendersFourAutoDetectedModules() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentDetailView.swift")

        // Detail is driven purely by the Core detail projection (no FS work).
        XCTAssertTrue(source.contains("let detail: AIAgentDetailProjection"))
        XCTAssertTrue(source.contains("private var overviewModule"))
        XCTAssertTrue(source.contains("private var storageModule"))
        XCTAssertTrue(source.contains("private var pluginsModule"))
        XCTAssertTrue(source.contains("private var skillsModule"))
        // Remote-vs-local honesty: notApplicable / empty states are surfaced.
        XCTAssertTrue(source.contains("case .notApplicable"))
        XCTAssertTrue(source.contains("case .empty"))
        XCTAssertTrue(source.contains("L10n.text(.aiAgentNotApplicable)"))
        XCTAssertTrue(source.contains("L10n.text(.aiAgentModuleEmpty)"))
        // Icons are rendered through the shared AgentIcon (installed app icon >
        // bundled asset > SF Symbol precedence resolved in Core).
        XCTAssertTrue(source.contains("AgentIcon(descriptor:"))
    }

    func testDeveloperAIViewFeedsCLIToolsFromAgentFilteredCLIList() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        // CLI Tools must consume the Agent-filtered CLI list (which excludes
        // agent-capable definitions like Aiden/Traex/Codex), never the raw
        // `aiManagementProjection.clis` that still contains agent CLIs.
        XCTAssertTrue(source.contains("clis: agentProjection.cliTools"))
        XCTAssertFalse(source.contains("clis: model.aiManagementProjection.clis"))
    }

    func testAIAgentDetailOverviewUsesDynamicFormFactorLabelNotHardcoded() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentDetailView.swift")

        // The form-factor row label is a single localized "Form factors" string;
        // the value is built dynamically from the entry's form factors, so a
        // cloud-only or single-form Agent shows honestly (no hardcoded "App / CLI").
        XCTAssertTrue(source.contains("L10n.text(.aiAgentFormFactors)"))
        XCTAssertFalse(source.contains("L10n.text(.aiAgentFormApp) + \" / \" + L10n.text(.aiAgentFormCLI)"))
        XCTAssertTrue(source.contains("formFactorLabels.joined(separator:"))
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
            XCTAssertTrue(source.contains("HSplitView"))
            XCTAssertTrue(source.contains("List(projection.groups"))
            XCTAssertFalse(source.contains(".onTapGesture"))
        }
    }

    func testProjectApprovalUIUsesSystemFolderPickerAndNoRowGestures() throws {
        let approval = try source(at: "Sources/SpacePilot/Views/DeveloperAI/ProjectApprovalBar.swift")
        XCTAssertTrue(approval.contains("NSOpenPanel()"))
        XCTAssertTrue(approval.contains("panel.canChooseDirectories = true"))
        XCTAssertTrue(approval.contains("panel.canChooseFiles = false"))
        XCTAssertTrue(approval.contains("onAddProjectRoot(url)"))
        XCTAssertTrue(approval.contains("onRemoveProjectRoot(root.id)"))
        XCTAssertFalse(approval.contains(".onTapGesture"))

        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains("projection.allSkills + model.projectAIAssetSkills"))
        XCTAssertTrue(shell.contains("projection.allPlugins + model.projectAIAssetPlugins"))
    }

    func testCLIToolsViewShowsHonestCoverageStatusAndRevealsExecutable() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")

        XCTAssertTrue(source.contains("let clis: [AIToolRecord]"))
        XCTAssertTrue(source.contains("tool.coverageFailures"))
        XCTAssertTrue(source.contains("evidence.executableURL"))
        XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal(urlAtRow:"))
        XCTAssertTrue(source.contains("PluginTableLayoutMode(availableWidth: geometry.size.width)"))
    }

    func testCLIToolsViewSurfacesAliasEvidenceAndRevealsAliases() throws {
        // Known aliases resolved to the same executable must be presented to the
        // user as evidence (Codex 5A-2: "别名作为 evidence 展示"), and each alias
        // must be revealable in Finder.
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")

        XCTAssertTrue(source.contains("tool.evidence.aliasExecutableURLs"))
        XCTAssertTrue(source.contains("L10n.text(.aiCLIAliases)"))
        XCTAssertTrue(source.contains("ForEach(tool.evidence.aliasExecutableURLs"))
        XCTAssertTrue(source.contains("FinderReveal.reveal(alias)"))
    }

    func testDeveloperAIShellOwnsPerSectionSelectionBindings() throws {
        // Selection state must live in the persistent shell so switching the
        // section (which destroys/recreates the conditional subtrees) does not
        // reset each page's selection.
        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains("@State private var selectedAIEntryID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedSkillGroupID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedSkillID: Set<UUID> = []"))
        XCTAssertTrue(shell.contains("@State private var selectedPluginGroupID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedPluginID: Set<UUID> = []"))
        XCTAssertTrue(shell.contains("@State private var selectedCLIID: Set<String> = []"))
        // The shell passes each selection down as a binding.
        XCTAssertTrue(shell.contains("selectedEntryID: $selectedAIEntryID"))
        XCTAssertTrue(shell.contains("selectedGroupID: $selectedSkillGroupID"))
        XCTAssertTrue(shell.contains("selection: $selectedSkillID"))
        XCTAssertTrue(shell.contains("selectedGroupID: $selectedPluginGroupID"))
        XCTAssertTrue(shell.contains("selection: $selectedPluginID"))
        XCTAssertTrue(shell.contains("selection: $selectedCLIID"))

        // The subviews must consume the selection as a @Binding and must not
        // declare their own @State selection that would be reset on rebuild.
        let apps = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentsSectionView.swift")
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
            // Skills/Plugins/CLI tables are multi-select (Set) so users can pick
            // several assets to check/update at once. A cell TapGesture would
            // break the native single/multi selection + double-click behavior.
            XCTAssertTrue(source.contains("@Binding var selection: Set<"))
            XCTAssertFalse(source.contains(".onTapGesture"))
        }
    }

    func testDeveloperAIAgentsRestoreSelectionViaLocalityFallback() throws {
        // AI Agents must keep a still-valid selection rather than clobbering it,
        // and fall back to the first local then first remote Agent on rebuild.
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentsSectionView.swift")
        XCTAssertTrue(source.contains("private func resolveSelection()"))
        XCTAssertTrue(source.contains("localAgents.first?.id ?? remoteAgents.first?.id"))
    }

    func testAIAgentsAndCLIDistinguishDiscoveringAndErrorStates() throws {
        // Empty/refresh states must not be reported as a bare "no data".
        let apps = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentsSectionView.swift")
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
