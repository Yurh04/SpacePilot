import SpacePilotCore
import SwiftUI

/// Read-only global Plugins page grouped by explicit owner/location scope.
struct GlobalPluginsView: View {
    let plugins: [PluginRecord]
    let discoveredToolIDs: Set<String>
    let approvedProjectRoots: [ApprovedProjectRoot]
    let approvedProjectRootIssues: [ApprovedProjectRootIssue]
    let projectScanIssues: [ProjectAIAssetScanIssue]
    let isScanningProjects: Bool
    let projectScanError: String?
    let searchText: String
    let onAddProjectRoot: (URL) -> Void
    let onRemoveProjectRoot: (String) -> Void
    let updateResults: [AIUpdateAssetKey: UpdateCheckResult]
    let isCheckingUpdates: Bool
    let updateAssets: [AIUpdateAsset]
    let onCheckSelectedUpdates: (Set<AIUpdateAssetKey>) -> Void
    let onUpdateSelected: (Set<AIUpdateAssetKey>) -> Void
    let onCancelUpdateCheck: () -> Void
    @Binding var selectedGroupID: String?
    @Binding var selection: Set<UUID>

    private var projection: GroupedPluginsProjection {
        GroupedPluginsProjection(plugins: plugins, discoveredToolIDs: discoveredToolIDs)
    }

    private var selectedRows: [AIUpdateSelectionPlan.SelectedRow] {
        filteredPlugins
            .filter { selection.contains($0.id) }
            .map { AIUpdateSelectionPlan.SelectedRow(key: AIUpdateKeyBuilder.key(for: $0), displayName: $0.name) }
    }

    private var selectionPlan: AIUpdateSelectionPlan {
        AIUpdateSelectionPlan(
            selection: selectedRows,
            assets: updateAssets,
            results: updateResults
        )
    }

    private var filteredPlugins: [PluginRecord] {
        guard let selectedGroupID else { return [] }
        return projection.plugins(in: selectedGroupID, matching: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectApprovalBar(
                approvedProjectRoots: approvedProjectRoots,
                approvedProjectRootIssues: approvedProjectRootIssues,
                projectScanIssues: projectScanIssues,
                isScanningProjects: isScanningProjects,
                projectScanError: projectScanError,
                onAddProjectRoot: onAddProjectRoot,
                onRemoveProjectRoot: onRemoveProjectRoot
            )
            Divider()
            if plugins.isEmpty {
                ContentUnavailableView(
                    L10n.noPluginsInstalled(),
                    systemImage: "puzzlepiece.extension"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if projection.groups.isEmpty {
                ContentUnavailableView(
                    L10n.text(.aiGroupEmpty),
                    systemImage: "folder.badge.questionmark"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    groupList
                        .frame(minWidth: 150, idealWidth: 190, maxWidth: 240)
                    VStack(spacing: 0) {
                        AIUpdateActionBar(
                            plan: selectionPlan,
                            isChecking: isCheckingUpdates,
                            onCheckSelected: { onCheckSelectedUpdates(Set(selectionPlan.checkableKeys)) },
                            onUpdateSelected: { onUpdateSelected(Set(selectionPlan.selected.map(\.key))) },
                            onCancel: onCancelUpdateCheck
                        )
                        Divider()
                        tableContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear(perform: resolveSelection)
        .onChange(of: projection.groups.map(\.id)) { _, _ in resolveSelection() }
        .onChange(of: selectedGroupID) { _, _ in resolveRowSelection() }
        .onChange(of: searchText) { _, _ in resolveRowSelection() }
    }

    private var groupList: some View {
        List(projection.groups, selection: $selectedGroupID) { group in
            HStack {
                Text(groupTitle(group))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(group.itemCount.formatted())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .tag(group.id)
        }
    }

    private func groupTitle(_ group: AIAssetGroup) -> String {
        switch group.kind {
        case .shared: L10n.text(.aiGroupSharedPlugins)
        case .tool, .unknown: group.title
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        GeometryReader { geometry in
            let layout = PluginTableLayoutMode(availableWidth: geometry.size.width)
            if selectedGroupID == nil {
                ContentUnavailableView(L10n.text(.aiGroupSelect), systemImage: "sidebar.left")
            } else if filteredPlugins.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(L10n.text(.aiStateNoResults), systemImage: "magnifyingglass")
            } else if filteredPlugins.isEmpty {
                ContentUnavailableView(L10n.text(.aiGroupNoItems), systemImage: "tray")
            } else if layout == .compact {
                compactTable
            } else {
                regularTable
            }
        }
    }

    private var compactTable: some View {
        Table(filteredPlugins, selection: $selection) {
            TableColumn(L10n.text(.plugin)) { plugin in
                pluginNameCell(plugin)
            }
            TableColumn(L10n.text(.aiUpdateStatus)) {
                Text(updateStatusText(for: $0))
                    .lineLimit(1)
            }
            .width(min: 90, ideal: 110, max: 130)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private var regularTable: some View {
        Table(filteredPlugins, selection: $selection) {
            TableColumn(L10n.text(.plugin)) { plugin in
                pluginNameCell(plugin)
            }
            TableColumn(L10n.text(.aiGroupScope)) {
                Text(scopeLabel(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 96, ideal: 120, max: 160)
            TableColumn(L10n.version()) {
                Text(currentVersionText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 76, max: 88)
            TableColumn(L10n.text(.aiUpdateLatest)) {
                Text(latestVersionText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 76, max: 88)
            TableColumn(L10n.skills()) {
                Text($0.skillCount.formatted())
                    .lineLimit(1)
            }
            .width(min: 52, ideal: 64, max: 76)
            TableColumn(L10n.text(.aiUpdateStatus)) {
                Text(updateStatusText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 90, ideal: 110, max: 130)
            TableColumn(L10n.space()) {
                Text(ByteCount.string($0.allocatedSize))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 92, max: 104)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private func pluginNameCell(_ plugin: PluginRecord) -> some View {
        VStack(alignment: .leading) {
            Text(plugin.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(plugin.source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .contextMenu {
            Button(L10n.text(.revealFinder)) { FinderReveal.reveal(plugin.url) }
        }
    }

    private func urlForRow(_ row: Int) -> URL? {
        filteredPlugins.indices.contains(row) ? filteredPlugins[row].url : nil
    }

    private func updateResult(for plugin: PluginRecord) -> UpdateCheckResult? {
        AIUpdateStatusPresentation.result(
            for: AIUpdateKeyBuilder.key(for: plugin),
            in: updateResults,
            isChecking: isCheckingUpdates
        )
    }

    private func updateStatusText(for plugin: PluginRecord) -> String {
        AIUpdateStatusPresentation.statusText(updateResult(for: plugin))
    }

    private func currentVersionText(for plugin: PluginRecord) -> String {
        AIUpdateStatusPresentation.currentVersion(updateResult(for: plugin), fallback: plugin.version)
    }

    private func latestVersionText(for plugin: PluginRecord) -> String {
        AIUpdateStatusPresentation.latestVersion(updateResult(for: plugin))
    }

    private func scopeLabel(for plugin: PluginRecord) -> String {
        L10n.scopeDetailLabel(projection.scopeDetail(for: plugin))
    }

    private func resolveSelection() {
        let oldSelection = selectedGroupID
        selectedGroupID = GroupedPluginsProjection.resolvedSelection(
            current: selectedGroupID,
            preferredOwnerFrom: oldSelection,
            groups: projection.groups
        )
        resolveRowSelection()
    }

    private func resolveRowSelection() {
        // Keep only still-visible rows selected; a group/search change must not
        // leave a phantom selection pointing at a filtered-out row.
        let visible = Set(filteredPlugins.map(\.id))
        selection = selection.intersection(visible)
    }
}
