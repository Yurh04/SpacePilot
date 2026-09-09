import SpacePilotCore
import SwiftUI

/// Developer & AI page shell. Presents a stable left-side section list
/// (Overview / AI Apps / Skills / Plugins / CLI Tools) and routes to the
/// matching read-only section view. This persistent shell owns the section
/// routing and each page's selection state (passed down as bindings) so that
/// switching sections never resets a page's selection and never pollutes
/// `selectedAIApplicationID` / `selectedAIApplicationTab`.
///
/// The internal layout uses `HSplitView` + a section `List` rather than a
/// nested split container to avoid a second sidebar-collapse/toolbar behavior
/// and to keep the narrowest-window width small (section ~140 + AI apps ~180 +
/// detail ~420).
struct DeveloperAIView: View {
    @Bindable var model: AppModel
    let projection: DeveloperAIProjection?
    let hasSnapshot: Bool
    @State private var sidebarRow: DeveloperAISidebarRow = .overview
    // Per-page selection is owned by this persistent shell (not the switched-in
    // subviews) so switching sections never resets a page's selection when
    // SwiftUI destroys/recreates the conditional child subtree.
    @State private var selectedSkillGroupID: String?
    @State private var selectedSkillID: Set<UUID> = []
    @State private var selectedPluginGroupID: String?
    @State private var selectedPluginID: Set<UUID> = []
    @State private var selectedCLIID: Set<String> = []

    /// The unified Agent projection: every piece of evidence sharing a
    /// `definitionID` collapses into one Agent, split by fixed locality.
    ///
    /// Rebuilt only when the underlying records change, not on every `body`
    /// evaluation: the detail pane reads it several times per render, and the
    /// projection is pure so caching cannot go stale while the records are equal.
    private var agentProjection: AIAgentProjection {
        AIAgentCache.shared.projection(for: model.aiManagementProjection.records)
    }

    /// Skills/plugins fed to the per-Agent detail modules. The detail projection
    /// keeps only assets owned by the selected Agent's definition, plus shared
    /// assets reported separately as `globalSkills`, so passing the full
    /// discovered set (global + project) never leaks another Agent's assets.
    private func agentSkills(_ projection: DeveloperAIProjection) -> [SkillRecord] {
        projection.allSkills + model.projectAIAssetSkills
    }

    private func agentPlugins(_ projection: DeveloperAIProjection) -> [PluginRecord] {
        projection.allPlugins + model.projectAIAssetPlugins
    }

    /// Allocated sizes keyed by each Agent data/config root's canonical path,
    /// aggregated from the snapshot items already in memory. No file-system
    /// traversal happens here, but canonicalising each path *is* a syscall, so
    /// this is computed in one pass for every Agent and cached against the
    /// snapshot identity rather than recomputed on each `body` evaluation.
    private var agentStorageSizesByPath: [String: Int64] {
        if !model.aiAgentStorage.isEmpty {
            return model.aiAgentStorage.values.reduce(into: [:]) { sizes, snapshot in
                sizes.merge(snapshot.sizesByPath, uniquingKeysWith: max)
            }
        }
        guard let snapshot = model.latestSnapshot, !snapshot.items.isEmpty else { return [:] }
        let agents = agentProjection.localAgents + agentProjection.remoteAgents
        return AIAgentCache.shared.storageSizes(
            snapshotID: snapshot.id,
            items: snapshot.items,
            agents: agents
        )
    }

    /// Per-Agent allocated sizes split by semantic category, for the detail pane's
    /// "space breakdown" chart. Same snapshot-cached one-pass aggregation as
    /// `agentStorageSizesByPath`, keyed by Agent id.
    private var agentStorageSizesByCategory: [String: [ItemCategory: Int64]] {
        guard let snapshot = model.latestSnapshot, !snapshot.items.isEmpty else { return [:] }
        let agents = agentProjection.localAgents + agentProjection.remoteAgents
        return AIAgentCache.shared.storageSizesByCategory(
            snapshotID: snapshot.id,
            items: snapshot.items,
            agents: agents
        )
    }

    /// Drives the confirmation sheet from the model's pending plan. Dismissing
    /// the sheet routes through `cancelAIUpdateExecution` so it has zero side
    /// effects when nothing is executing.
    private var updateSheetBinding: Binding<Bool> {
        Binding(
            get: { model.pendingUpdatePlan != nil },
            set: { presented in
                if !presented { model.cancelAIUpdateExecution() }
            }
        )
    }

    var body: some View {
        if let projection {
            HSplitView {
                sidebar(projection)
                    .frame(minWidth: 170, idealWidth: 195, maxWidth: 230)
                rowContent(projection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(L10n.developerAI())
            .sheet(isPresented: updateSheetBinding) {
                if let plan = model.pendingUpdatePlan {
                    AIUpdateConfirmSheet(
                        plan: plan,
                        isExecuting: model.isExecutingAIUpdates,
                        results: model.aiUpdateExecutionResults,
                        executionError: model.aiUpdateExecutionError,
                        onConfirm: model.confirmAIUpdateExecution,
                        onClose: model.cancelAIUpdateExecution
                    )
                }
            }
        } else if hasSnapshot {
            ProgressView(L10n.preparingSummary())
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(L10n.developerAI())
        } else {
            ContentUnavailableView(
                L10n.developerAI(),
                systemImage: "sparkles.rectangle.stack",
                description: Text(L10n.text(.aiStateNotScanned))
            )
            .navigationTitle(L10n.developerAI())
        }
    }

    /// Every discovered AI, local first then remote, matching the order the
    /// Agent projection already establishes.
    private var allAgents: [AIAgentEntry] {
        agentProjection.localAgents + agentProjection.remoteAgents
    }

    /// Overview, then one row per discovered AI, then the capability rows.
    ///
    /// A single flat `List` (rather than `Section`s) keeps selection behaviour
    /// identical across all three tiers; the group headers are plain rows that
    /// cannot be selected.
    private func sidebar(_ projection: DeveloperAIProjection) -> some View {
        let duplicateCount = SkillDuplicationAnalyzer.analyze(
            skills: projection.allSkills + model.projectAIAssetSkills
        ).duplicatedEntityCount
        return List(selection: $sidebarRow) {
            Label(DeveloperAISidebarRow.overview.title,
                  systemImage: DeveloperAISidebarRow.overview.systemImage)
                .badge(duplicateCount > 0 ? duplicateCount : 0)
                .tag(DeveloperAISidebarRow.overview)

            if !allAgents.isEmpty {
                sidebarHeader(L10n.text(.aiSectionApps))
                ForEach(allAgents) { agent in
                    Label {
                        Text(agent.displayName)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } icon: {
                        // The real application icon, so the row is recognisable
                        // at a glance rather than a generic glyph.
                        AgentIcon(descriptor: agent.icon, size: 16)
                    }
                    .tag(DeveloperAISidebarRow.agent(id: agent.id))
                    .contextMenu {
                        // Reveal uses the Agent's own evidence: the installed
                        // application bundle when there is one, otherwise the
                        // controlled CLI executable.
                        if let url = agent.applicationURL ?? agent.executableURL {
                            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
                        }
                    }
                }
            }

            sidebarHeader(L10n.text(.aiGroupCapabilities))
            ForEach(DeveloperAISidebarRow.capabilityRows) { row in
                Label(row.title, systemImage: row.systemImage)
                    .badge(capabilityCount(row, projection: projection))
                    .tag(row)
            }
        }
    }

    /// Count shown beside a capability row, mirroring what the row's page lists so
    /// the sidebar and content never disagree. Zero renders as no badge.
    private func capabilityCount(_ row: DeveloperAISidebarRow, projection: DeveloperAIProjection) -> Int {
        switch row {
        case .skills:
            return (projection.allSkills + model.projectAIAssetSkills).count
        case .mcp:
            return model.aiCapabilities.mcpServers.count
        case .plugins:
            return (projection.allPlugins + model.projectAIAssetPlugins).count
        case .cli:
            return cliClassification.commandLineTools.count
        case .otherTools:
            return otherTools.count
        default:
            return 0
        }
    }

    private func sidebarHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            // Headers are labels, not destinations: excluding them from
            // selection keeps arrow-key navigation on real rows only.
            .selectionDisabled()
    }

    @ViewBuilder
    private func rowContent(_ projection: DeveloperAIProjection) -> some View {
        switch sidebarRow {
        case .overview:
            overviewSection(projection)
        case .agent(let id):
            agentDetail(id: id, projection: projection)
        case .skills:
            skillsSection(projection)
        case .mcp:
            MCPServersView(
                servers: model.aiCapabilities.mcpServers,
                agents: allAgents,
                searchText: model.searchText
            )
        case .plugins:
            pluginsSection(projection)
        case .cli:
            cliSection
        case .otherTools:
            OtherAIToolsView(
                tools: otherTools,
                agents: allAgents,
                searchText: model.searchText
            )
        }
    }

    /// The detail pane for one selected AI. Falls back to the Overview when the
    /// selected Agent disappears between scans, so the pane can never be blank.
    @ViewBuilder
    private func agentDetail(id: String, projection: DeveloperAIProjection) -> some View {
        if let agent = allAgents.first(where: { $0.id == id }) {
            AIAgentDetailView(
                detail: AIAgentDetailProjection(
                    agent: agent,
                    skills: agentSkills(projection),
                    plugins: agentPlugins(projection),
                    storageSizesByPath: agentStorageSizesByPath,
                    storageSizesByCategory: model.aiAgentStorage[id] == nil
                        ? agentStorageSizesByCategory[id] ?? [:] : [:],
                    storageSnapshot: model.aiAgentStorage[id]
                ),
                mcpServers: model.aiCapabilities.mcpServers.filter { $0.ownerDefinitionID == id },
                hooks: model.aiCapabilities.hooks.filter { $0.ownerDefinitionID == id },
                instructionFiles: model.aiCapabilities.instructionFiles
                    .filter { $0.ownerDefinitionID == id },
                configProfile: model.aiCapabilities.configProfiles.first { $0.ownerDefinitionID == id },
                revealURL: agent.applicationURL ?? agent.executableURL,
                formFactorLabels: formFactorLabels(agent.formFactors),
                isDiscovering: model.isDiscoveringAITools,
                cliUpdateAssets: model.aiUpdateAssets.filter { $0.key.kind == .cli && $0.definitionID == id },
                updateResults: model.aiUpdateResults,
                isCheckingUpdates: model.isCheckingAIUpdates,
                isExecutingUpdates: model.isExecutingAIUpdates,
                updateError: model.aiUpdateError,
                onCheckUpdates: model.checkAIUpdatesForSelection,
                onUpdate: model.prepareAIUpdateExecution
            )
        } else {
            overviewSection(projection)
        }
    }

    /// Human-readable form-factor labels, in a fixed order so an Agent that is
    /// both an app and a CLI always reads the same way.
    private func formFactorLabels(_ formFactors: Set<AIAgentFormFactor>) -> [String] {
        var labels: [String] = []
        if formFactors.contains(.application) { labels.append(L10n.text(.aiAgentFormApp)) }
        if formFactors.contains(.cli) { labels.append(L10n.text(.aiAgentFormCLI)) }
        if formFactors.contains(.cloud) { labels.append(L10n.text(.aiAgentFormCloud)) }
        return labels
    }

    /// Splits agent-projection CLI tools into genuine per-Agent command-line
    /// tools and standalone "other AI tools", using runtime heuristics plus the
    /// discovered MCP evidence. Computed once and reused by both the CLI list and
    /// the Other AI tools list so the two never disagree.
    private var cliClassification: SupportingCLIClassifier.Result {
        SupportingCLIClassifier.classify(
            cliRecords: agentProjection.cliTools,
            mcpServers: model.aiCapabilities.mcpServers
        )
    }

    private var otherTools: [OtherAIToolRecord] {
        OtherAIToolProjection.tools(
            hooks: model.aiCapabilities.hooks,
            mcpServers: model.aiCapabilities.mcpServers,
            reclassifiedCLIs: cliClassification.otherTools,
            pipxTools: model.pipxAITools,
            configManagers: model.configManagerTools
        )
    }

    @ViewBuilder
    private func overviewSection(_ projection: DeveloperAIProjection) -> some View {
        let duplication = SkillDuplicationAnalyzer.analyze(
            skills: projection.allSkills + model.projectAIAssetSkills
        )
        AIManagementOverviewView(
            managementProjection: model.aiManagementProjection,
            appCount: AIApplicationJoin.applicationCount(
                deepApplications: projection.applications.map(\.application),
                registryApplications: model.aiManagementProjection.applications
            ),
            cliCount: cliClassification.commandLineTools.count,
            globalSkillCount: projection.allSkills.count,
            globalPluginCount: projection.allPlugins.count,
            duplication: duplication,
            healthFindings: AIHealthFindings.analyze(
                duplication: duplication,
                sizesByPath: agentStorageSizesByPath,
                hooks: model.aiCapabilities.hooks,
                skills: projection.allSkills + model.projectAIAssetSkills
            ),
            mcpCount: model.aiCapabilities.mcpServers.count,
            hookCount: model.aiCapabilities.hooks.count,
            isDiscovering: model.isDiscoveringAITools,
            discoveryError: model.aiDiscoveryError,
            updateSummary: model.aiUpdateSummary,
            isCheckingUpdates: model.isCheckingAIUpdates,
            updateError: model.aiUpdateError,
            onCheckUpdates: model.checkAIUpdatesNow,
            onCancelUpdateCheck: model.cancelAIUpdateCheck
        )
    }

    @ViewBuilder
    private func skillsSection(_ projection: DeveloperAIProjection) -> some View {
        GlobalSkillsView(
            skills: projection.allSkills + model.projectAIAssetSkills,
            plugins: projection.allPlugins + model.projectAIAssetPlugins,
            discoveredToolIDs: model.aiManagementProjection.discoveredToolDefinitionIDs,
            approvedProjectRoots: model.approvedProjectRoots,
            approvedProjectRootIssues: model.approvedProjectRootIssues,
            projectScanIssues: model.projectAIAssetScanIssues,
            isScanningProjects: model.isScanningProjectAIAssets,
            projectScanError: model.projectAIAssetError,
            searchText: model.searchText,
            onAddProjectRoot: model.addApprovedProjectRoot,
            onRemoveProjectRoot: model.removeApprovedProjectRoot,
            updateResults: model.aiUpdateResults,
            isCheckingUpdates: model.isCheckingAIUpdates,
            updateAssets: model.aiUpdateAssets,
            onCheckSelectedUpdates: model.checkAIUpdatesForSelection,
            onUpdateSelected: model.prepareAIUpdateExecution,
            onCancelUpdateCheck: model.cancelAIUpdateCheck,
            selectedGroupID: $selectedSkillGroupID,
            selection: $selectedSkillID
        )
    }

    @ViewBuilder
    private func pluginsSection(_ projection: DeveloperAIProjection) -> some View {
        GlobalPluginsView(
            plugins: projection.allPlugins + model.projectAIAssetPlugins,
            discoveredToolIDs: model.aiManagementProjection.discoveredToolDefinitionIDs,
            approvedProjectRoots: model.approvedProjectRoots,
            approvedProjectRootIssues: model.approvedProjectRootIssues,
            projectScanIssues: model.projectAIAssetScanIssues,
            isScanningProjects: model.isScanningProjectAIAssets,
            projectScanError: model.projectAIAssetError,
            searchText: model.searchText,
            onAddProjectRoot: model.addApprovedProjectRoot,
            onRemoveProjectRoot: model.removeApprovedProjectRoot,
            updateResults: model.aiUpdateResults,
            isCheckingUpdates: model.isCheckingAIUpdates,
            updateAssets: model.aiUpdateAssets,
            onCheckSelectedUpdates: model.checkAIUpdatesForSelection,
            onUpdateSelected: model.prepareAIUpdateExecution,
            onCancelUpdateCheck: model.cancelAIUpdateCheck,
            selectedGroupID: $selectedPluginGroupID,
            selection: $selectedPluginID
        )
    }

    private var cliSection: some View {
        CLIToolsView(
            clis: cliClassification.commandLineTools,
            searchText: model.searchText,
            isDiscovering: model.isDiscoveringAITools,
            discoveryError: model.aiDiscoveryError,
            updateResults: model.aiUpdateResults,
            isCheckingUpdates: model.isCheckingAIUpdates,
            updateAssets: model.aiUpdateAssets,
            onCheckSelectedUpdates: model.checkAIUpdatesForSelection,
            onUpdateSelected: model.prepareAIUpdateExecution,
            onCancelUpdateCheck: model.cancelAIUpdateCheck,
            selection: $selectedCLIID
        )
    }
}
