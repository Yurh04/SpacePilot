import Foundation
import XCTest

final class DeveloperAIArchitectureTests: XCTestCase {
    func testAgentCollapseIconsCompactSizeAndUpdateSelectionWiring() throws {
        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains("if agentsExpanded"))
        XCTAssertTrue(shell.contains("agentsExpanded.toggle()"))
        for file in ["GlobalSkillsView", "GlobalPluginsView"] {
            let view = try source(at: "Sources/SpacePilot/Views/DeveloperAI/\(file).swift")
            XCTAssertTrue(view.contains("agents: agents"))
            XCTAssertFalse(view.contains("Set(selectionPlan.checkableKeys)"))
        }
        let skills = try source(at: "Sources/SpacePilot/Views/DeveloperAI/GlobalSkillsView.swift")
        let compact = skills.components(separatedBy: "private var compactTable")[1].components(separatedBy: "private var regularTable")[0]
        XCTAssertTrue(compact.contains("ByteCount.string($0.allocatedSize)"))
        let cli = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")
        XCTAssertFalse(cli.contains("Set(selectionPlan.checkableKeys)"))
        let other = try source(at: "Sources/SpacePilot/Views/DeveloperAI/OtherAIToolsView.swift")
        XCTAssertTrue(other.contains("AIUpdateActionBar("))
        XCTAssertTrue(other.contains("AIUpdateIdentity.other"))
    }
    func testDeveloperAIViewUsesStableSectionListNotSegmentedPicker() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        XCTAssertTrue(source.contains("List(selection: $sidebarRow)"))
        XCTAssertTrue(source.contains("DeveloperAISidebarRow.capabilityRows"))
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
        XCTAssertTrue(source.contains("AIAgentDetailView("))
        XCTAssertTrue(source.contains("MCPServersView("))
        XCTAssertTrue(source.contains("OtherAIToolsView("))
        XCTAssertTrue(source.contains("GlobalSkillsView("))
        XCTAssertTrue(source.contains("GlobalPluginsView("))
        XCTAssertTrue(source.contains("CLIToolsView("))
    }

    func testDeveloperAIViewBuildsAgentProjectionByDefinitionNotDisplayName() throws {
        let viewSource = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        let cacheSource = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentCache.swift")

        // Agents are unified from discovered records via the Core projection,
        // which joins by stable definitionID (never by display name). The view
        // reaches it through the memoising cache, which is the only place that
        // constructs the projection.
        XCTAssertTrue(viewSource.contains("AIAgentCache.shared.projection(for: model.aiManagementProjection.records)"))
        XCTAssertTrue(cacheSource.contains("AIAgentProjection(records: records)"))
        XCTAssertFalse(viewSource.contains("AIApplicationJoin.registryOnlyApplications("))
    }

    /// The detail pane is re-rendered on every selection change and keystroke, so
    /// the expensive projections must be memoised rather than rebuilt inside
    /// `body`. Rebuilding them per access previously cost hundreds of
    /// milliseconds per render on a real snapshot.
    func testExpensiveAIProjectionsAreMemoisedNotRebuiltPerBody() throws {
        let developerAI = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        let skillsSource = try source(at: "Sources/SpacePilot/Views/DeveloperAI/GlobalSkillsView.swift")
        let pluginsSource = try source(at: "Sources/SpacePilot/Views/DeveloperAI/GlobalPluginsView.swift")

        // No view may construct these projections directly; they go through the cache.
        XCTAssertFalse(developerAI.contains("AIAgentProjection(records:"))
        XCTAssertFalse(skillsSource.contains("GroupedSkillsProjection(skills:"))
        XCTAssertFalse(pluginsSource.contains("GroupedPluginsProjection(plugins:"))
        XCTAssertTrue(skillsSource.contains("AIAgentCache.shared.groupedSkills("))
        XCTAssertTrue(pluginsSource.contains("AIAgentCache.shared.groupedPlugins("))

        // Storage sizes are bucketed for all agents in one pass, not per agent.
        XCTAssertFalse(developerAI.contains("storageSizes(items: items, forAgent:"))
        XCTAssertTrue(developerAI.contains("AIAgentCache.shared.storageSizes("))
    }

    /// Agents are top-level sidebar rows, at the same level as the capability
    /// rows, and each shows its real application icon rather than a generic glyph.
    func testAgentsAreTopLevelSidebarRowsWithRealIcons() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")

        // Overview first, then one row per discovered AI, then capabilities.
        let overview = try XCTUnwrap(source.range(of: "DeveloperAISidebarRow.overview"))
        let agents = try XCTUnwrap(source.range(of: "ForEach(allAgents)"))
        let caps = try XCTUnwrap(source.range(of: "ForEach(DeveloperAISidebarRow.capabilityRows)"))
        XCTAssertTrue(overview.lowerBound < agents.lowerBound)
        XCTAssertTrue(agents.lowerBound < caps.lowerBound)

        // The real app icon, not an SF Symbol placeholder.
        XCTAssertTrue(source.contains("AgentIcon(descriptor: agent.icon"))
        // Group headers must not be selectable, or arrow-key navigation lands
        // on a label that routes nowhere.
        XCTAssertTrue(source.contains(".selectionDisabled()"))
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
        // `aiManagementProjection.clis` that still contains agent CLIs. It now
        // flows through the supporting-CLI classifier, whose input is
        // `agentProjection.cliTools`, so agent CLIs remain excluded.
        XCTAssertTrue(source.contains("cliClassification.commandLineTools"))
        XCTAssertTrue(source.contains("cliRecords: agentProjection.cliTools"))
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
            XCTAssertTrue(source.contains("let groups = projection.groups"))
            XCTAssertTrue(source.contains("List(groups, selection: $selectedGroupID)"))
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
        XCTAssertTrue(shell.contains("@State private var sidebarRow: DeveloperAISidebarRow"))
        XCTAssertTrue(shell.contains("@State private var selectedSkillGroupID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedSkillID: Set<UUID> = []"))
        XCTAssertTrue(shell.contains("@State private var selectedPluginGroupID: String?"))
        XCTAssertTrue(shell.contains("@State private var selectedPluginID: Set<UUID> = []"))
        XCTAssertTrue(shell.contains("@State private var selectedCLIID: Set<String> = []"))
        // The shell passes each selection down as a binding.
        XCTAssertTrue(shell.contains("selectedGroupID: $selectedSkillGroupID"))
        XCTAssertTrue(shell.contains("selection: $selectedSkillID"))
        XCTAssertTrue(shell.contains("selectedGroupID: $selectedPluginGroupID"))
        XCTAssertTrue(shell.contains("selection: $selectedPluginID"))
        XCTAssertTrue(shell.contains("selection: $selectedCLIID"))

        // The subviews must consume the selection as a @Binding and must not
        // declare their own @State selection that would be reset on rebuild.

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

    /// Selecting an Agent that disappears between scans must fall back to a
    /// valid pane rather than rendering blank.
    func testMissingAgentSelectionFallsBackToOverview() throws {
        let source = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(source.contains("if let agent = allAgents.first(where: { $0.id == id })"))
        XCTAssertTrue(source.contains("} else {\n            overviewSection(projection)"))
    }

    func testAIAgentsAndCLIDistinguishDiscoveringAndErrorStates() throws {
        // Empty/refresh states must not be reported as a bare "no data".
        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains("isDiscovering"))
        XCTAssertTrue(shell.contains("discoveryError"))

        let cli = try source(at: "Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift")
        XCTAssertTrue(cli.contains("isDiscovering"))
        XCTAssertTrue(cli.contains("discoveryError"))
        // A lightweight refresh banner keeps existing read-only data visible.
        XCTAssertTrue(cli.contains("AIDiscoveryBanner"))
    }

    func testSidebarSeparatesCustomCollapseHoverFromNativeSelectableRows() throws {
        let shell = try source(at: "Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift")
        XCTAssertTrue(shell.contains(".buttonStyle(.plain)\n                .interactiveHover(cornerRadius: 6)"))
        XCTAssertTrue(shell.contains("let hoverRows = DeveloperAISidebarHoverRows.make("))
        XCTAssertTrue(shell.contains("hoverRows.indices.contains(row) && hoverRows[row]"))
        XCTAssertEqual(shell.components(separatedBy: ".interactiveHover").count - 1, 1,
            "Selectable Agent rows and the read-only capabilities header use no custom hover")
        let callback = try XCTUnwrap(shell.range(of: ".nativeTableHoverHighlight { row in"))
        let closure = shell[callback.lowerBound...].components(separatedBy: "\n        }")[0]
        XCTAssertFalse(closure.contains("allAgents"), "Pointer updates must use the precomputed visible rows")
    }

    func testAgentDetailHoverCoversRevealRowsAndLeavesSummaryChromeReadOnly() throws {
        let detail = try source(at: "Sources/SpacePilot/Views/DeveloperAI/AIAgentDetailView.swift")
        for target in ["file.url", "server.sourceURL", "hook.sourceURL", "item.url", "url"] {
            let gesture = try XCTUnwrap(detail.range(of: ".onDoubleClickRevealInFinder(\(target))"))
            XCTAssertTrue(detail[gesture.lowerBound...].prefix(150).contains(".interactiveHover"), target)
        }
        XCTAssertTrue(detail.contains(".interactiveHover(isEnabled: revealURL != nil"))
        XCTAssertFalse(detail.contains(".nativeTableHoverHighlight"), "Agent detail has custom rows, not an NSTableView")
        for (start, end) in [("private var breakdownModule", "// MARK: - Plugins module"),
                             ("private func moduleCard", "private var moduleEmpty")] {
            let lower = try XCTUnwrap(detail.range(of: start)).lowerBound
            let upper = try XCTUnwrap(detail.range(of: end, range: lower..<detail.endIndex)).lowerBound
            XCTAssertFalse(detail[lower..<upper].contains(".interactiveHover"), start)
        }
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
