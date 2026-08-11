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
    @State private var section: AIManagementSection = .overview
    // Per-page selection is owned by this persistent shell (not the switched-in
    // subviews) so switching sections never resets a page's selection when
    // SwiftUI destroys/recreates the conditional child subtree.
    @State private var selectedAIEntryID: String?
    @State private var selectedSkillGroupID: String?
    @State private var selectedSkillID: Set<UUID> = []
    @State private var selectedPluginGroupID: String?
    @State private var selectedPluginID: Set<UUID> = []
    @State private var selectedCLIID: Set<String> = []

    /// The unified Agent projection: every piece of evidence sharing a
    /// `definitionID` collapses into one Agent, split by fixed locality.
    private var agentProjection: AIAgentProjection {
        AIAgentProjection(records: model.aiManagementProjection.records)
    }

    /// Skills/plugins fed to the per-Agent detail modules. The detail projection
    /// keeps only assets owned by the selected Agent's definition, so passing the
    /// full discovered set (global + project) is safe and never leaks shared or
    /// other-Agent assets into a given Agent's module.
    private func agentSkills(_ projection: DeveloperAIProjection) -> [SkillRecord] {
        projection.allSkills + model.projectAIAssetSkills
    }

    private func agentPlugins(_ projection: DeveloperAIProjection) -> [PluginRecord] {
        projection.allPlugins + model.projectAIAssetPlugins
    }

    /// Allocated sizes keyed by each Agent data/config root's canonical path,
    /// aggregated from the snapshot items already in memory. Computed once here
    /// (not per row) and shared across every Agent's Data & Storage module. No
    /// file-system access happens: `AIAgentDetailProjection.storageSizes` is a
    /// pure bucketing over items the scan already produced.
    private var agentStorageSizesByPath: [String: Int64] {
        let items = model.latestSnapshot?.items ?? []
        guard !items.isEmpty else { return [:] }
        let agents = agentProjection.localAgents + agentProjection.remoteAgents
        var merged: [String: Int64] = [:]
        for agent in agents {
            for (path, size) in AIAgentDetailProjection.storageSizes(items: items, forAgent: agent) {
                merged[path] = size
            }
        }
        return merged
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
                List(AIManagementSection.allCases, selection: $section) { entry in
                    Label(
                        L10n.aiSectionTitle(for: entry),
                        systemImage: entry.systemImage
                    )
                    .tag(entry)
                }
                .frame(minWidth: 140, idealWidth: 160, maxWidth: 190)
                sectionContent(projection)
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

    @ViewBuilder
    private func sectionContent(_ projection: DeveloperAIProjection) -> some View {
        switch section {
        case .overview:
            AIManagementOverviewView(
                managementProjection: model.aiManagementProjection,
                appCount: AIApplicationJoin.applicationCount(
                    deepApplications: projection.applications.map(\.application),
                    registryApplications: model.aiManagementProjection.applications
                ),
                globalSkillCount: projection.allSkills.count,
                globalPluginCount: projection.allPlugins.count,
                isDiscovering: model.isDiscoveringAITools,
                discoveryError: model.aiDiscoveryError,
                updateSummary: model.aiUpdateSummary,
                isCheckingUpdates: model.isCheckingAIUpdates,
                updateError: model.aiUpdateError,
                onCheckUpdates: model.checkAIUpdatesNow,
                onCancelUpdateCheck: model.cancelAIUpdateCheck
            )
        case .apps:
            AIAgentsSectionView(
                projection: agentProjection,
                skills: agentSkills(projection),
                plugins: agentPlugins(projection),
                storageSizesByPath: agentStorageSizesByPath,
                selectedEntryID: $selectedAIEntryID,
                isDiscovering: model.isDiscoveringAITools,
                discoveryError: model.aiDiscoveryError
            )
        case .skills:
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
        case .plugins:
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
        case .cli:
            CLIToolsView(
                clis: agentProjection.cliTools,
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
}
