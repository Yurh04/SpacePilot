import SpacePilotCore
import SwiftUI

/// Read-only global Plugins page grouped by explicit owner/location scope.
struct GlobalPluginsView: View {
    let plugins: [PluginRecord]
    let approvedProjectRoots: [ApprovedProjectRoot]
    let approvedProjectRootIssues: [ApprovedProjectRootIssue]
    let projectScanIssues: [ProjectAIAssetScanIssue]
    let isScanningProjects: Bool
    let projectScanError: String?
    let searchText: String
    let onAddProjectRoot: (URL) -> Void
    let onRemoveProjectRoot: (String) -> Void
    @Binding var selectedGroupID: String?
    @Binding var selection: UUID?

    private var projection: GroupedPluginsProjection {
        GroupedPluginsProjection(plugins: plugins)
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
                    tableContent
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
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(group.title)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(group.itemCount.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(groupDetail(group))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .tag(group.id)
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
            TableColumn(L10n.space()) {
                Text(ByteCount.string($0.allocatedSize))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 76, ideal: 92, max: 104)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private var regularTable: some View {
        Table(filteredPlugins, selection: $selection) {
            TableColumn(L10n.text(.plugin)) { plugin in
                pluginNameCell(plugin)
            }
            TableColumn(L10n.version()) {
                Text($0.version ?? "—")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 76, max: 88)
            TableColumn(L10n.skills()) {
                Text($0.skillCount.formatted())
                    .lineLimit(1)
            }
            .width(min: 52, ideal: 64, max: 76)
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

    private func groupDetail(_ group: AIAssetGroup) -> String {
        "\(localizedDetail(group.detail)) · \(ByteCount.string(group.allocatedSize))"
    }

    private func localizedDetail(_ detail: String) -> String {
        switch detail {
        case "Global": L10n.text(.aiGroupGlobal)
        case "Project": L10n.text(.aiGroupProject)
        case let detail where detail.hasPrefix("Project · "):
            L10n.text(.aiGroupProject) + String(detail.dropFirst("Project".count))
        case "Bundled": L10n.text(.aiGroupBundled)
        case "System": L10n.text(.aiGroupSystem)
        default: L10n.text(.aiGroupUnknown)
        }
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
        if let selection, filteredPlugins.contains(where: { $0.id == selection }) { return }
        selection = filteredPlugins.first?.id
    }
}
