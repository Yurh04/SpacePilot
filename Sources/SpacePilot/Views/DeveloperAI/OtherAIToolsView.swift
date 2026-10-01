import SpacePilotCore
import SwiftUI

/// Read-only "other AI tools" page: tools that are not Agents themselves but
/// strengthen or manage the Agents on this machine.
///
/// Only tools backed by real evidence appear here — an app is listed as a hook
/// provider because its absolute path occurs in a hook command, and as an MCP
/// server because an Agent's config registers it. The "used by" column is what
/// makes the page useful: it answers which Agents a tool actually affects.
struct OtherAIToolsView: View {
    let tools: [OtherAIToolRecord]
    let agents: [AIAgentEntry]
    let searchText: String
    var updateAssets: [AIUpdateAsset] = []
    var updateResults: [AIUpdateAssetKey: UpdateCheckResult] = [:]
    var isCheckingUpdates = false
    var onCheckSelectedUpdates: (Set<AIUpdateAssetKey>) -> Void = { _ in }
    var onUpdateSelected: (Set<AIUpdateAssetKey>) -> Void = { _ in }
    var onCancelUpdateCheck: () -> Void = {}
    @State private var selection: Set<String> = []

    private var selectionPlan: AIUpdateSelectionPlan {
        AIUpdateSelectionPlan(selection: filtered.filter { selection.contains($0.id) }.map {
            .init(key: AIUpdateIdentity.other($0, assets: updateAssets), displayName: $0.name)
        }, assets: updateAssets, results: updateResults)
    }

    private func updateStatus(_ tool: OtherAIToolRecord) -> String {
        AIUpdateStatusPresentation.statusText(AIUpdateStatusPresentation.result(
            for: AIUpdateIdentity.other(tool, assets: updateAssets),
            in: updateResults, isChecking: isCheckingUpdates
        ))
    }

    private var filtered: [OtherAIToolRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tools }
        return tools.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func displayName(forAgent id: String) -> String {
        agents.first { $0.contains(definitionID: id) }?.displayName ?? id
    }

    /// The Agents a tool touches, named rather than shown as raw IDs. Truncated
    /// past three so a tool wired into many Agents does not stretch the column.
    private func usedByText(_ tool: OtherAIToolRecord) -> String {
        guard !tool.affectedAgentIDs.isEmpty else { return "—" }
        let names = Array(Set(tool.affectedAgentIDs.map(displayName(forAgent:)))).sorted()
        if names.count <= 3 { return names.joined(separator: " · ") }
        return names.prefix(3).joined(separator: " · ")
            + L10n.andMore(names.count - 3)
    }

    private func kindText(_ kind: OtherAIToolKind) -> String {
        switch kind {
        case .configurationManager: L10n.text(.aiOtherKindConfigManager)
        case .hookProvider: L10n.text(.aiOtherKindHookProvider)
        case .mcpServer: L10n.text(.aiOtherKindMCPServer)
        case .pluginSource: L10n.text(.aiOtherKindPluginSource)
        case .packageInstalled: L10n.text(.aiOtherKindPackage)
        }
    }

    private func installText(_ method: OtherAIToolInstallMethod) -> String {
        switch method {
        case .applicationBundle: L10n.text(.aiOtherInstallApp)
        case .npm: "npm"
        case .homebrew: "Homebrew"
        case .pipx: "pipx"
        case .mcpRegistration: L10n.text(.aiOtherInstallMCP)
        case .unknown: "—"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AIWorkspaceHeader(title: L10n.text(.aiSectionOtherTools), systemImage: "wrench.and.screwdriver", count: tools.count)
            Divider()
            if !tools.isEmpty {
                AIUpdateActionBar(plan: selectionPlan, isChecking: isCheckingUpdates,
                    onCheckSelected: { onCheckSelectedUpdates(Set(selectionPlan.selected.map(\.key))) },
                    onUpdateSelected: { onUpdateSelected(Set(selectionPlan.selected.map(\.key))) },
                    onCancel: onCancelUpdateCheck)
                Divider()
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var content: some View {
        if tools.isEmpty {
            ContentUnavailableView(
                L10n.text(.aiOtherToolsEmpty),
                systemImage: "wrench.and.screwdriver"
            )
        } else if filtered.isEmpty {
            ContentUnavailableView(
                L10n.text(.aiStateNoResults),
                systemImage: "magnifyingglass"
            )
        } else {
            GeometryReader { geometry in
                if PluginTableLayoutMode(availableWidth: geometry.size.width) == .compact {
                    compactTable
                } else {
                    regularTable
                }
            }
        }
    }

    private var regularTable: some View {
        let visibleTools = filtered
        return Table(visibleTools, selection: $selection) {
            TableColumn(L10n.text(.name)) { tool in
                AIAssetIdentity(name: tool.name, subtitle: tool.url.path, url: tool.url)
            }
            TableColumn(L10n.text(.aiUpdateStatus)) { Text(updateStatus($0)).lineLimit(2) }
                .width(min: 90, ideal: 110, max: 145)
            TableColumn(L10n.text(.aiOtherKind)) { tool in
                Text(kindText(tool.kind))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 84, ideal: 110, max: 150)
            TableColumn(L10n.text(.aiOtherInstall)) { tool in
                Text(installText(tool.installMethod))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 70, ideal: 92, max: 120)
            TableColumn(L10n.text(.aiMCPUsedBy)) { tool in
                Text(usedByText(tool))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 110, ideal: 170, max: 260)
        }
        .nativeTableHoverHighlight { row in
            visibleTools.indices.contains(row)
        }
        .nativeTableDoubleClickReveal { row in
            guard visibleTools.indices.contains(row) else { return nil }
            return visibleTools[row].url
        }
    }

    private var compactTable: some View {
        let visibleTools = filtered
        return Table(visibleTools, selection: $selection) {
            TableColumn(L10n.text(.name)) { tool in
                AIAssetIdentity(name: tool.name, subtitle: tool.url.path, url: tool.url)
            }
            TableColumn(L10n.text(.aiUpdateStatus)) { Text(updateStatus($0)).lineLimit(2) }
                .width(min: 90, ideal: 110, max: 145)
            TableColumn(L10n.text(.aiMCPUsedBy)) { tool in
                Text(usedByText(tool)).lineLimit(2).truncationMode(.tail)
            }
            .width(min: 72, ideal: 100, max: 130)
        }
        .nativeTableHoverHighlight { row in
            visibleTools.indices.contains(row)
        }
        .nativeTableDoubleClickReveal { row in
            guard visibleTools.indices.contains(row) else { return nil }
            return visibleTools[row].url
        }
    }
}
