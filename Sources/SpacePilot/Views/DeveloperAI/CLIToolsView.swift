import SpacePilotCore
import SwiftUI

/// Read-only CLI tools page. Uses `AIManagementProjection.clis` and shows
/// name / version / executable path / owner / coverage status. When a tool has
/// no version but carries a coverage failure, the failure is shown honestly —
/// it is never presented as "not installed". Double-click reveals the
/// executable URL via the native adapter.
struct CLIToolsView: View {
    let clis: [AIToolRecord]
    let searchText: String
    let isDiscovering: Bool
    let discoveryError: String?
    let updateResults: [AIUpdateAssetKey: UpdateCheckResult]
    let isCheckingUpdates: Bool
    let updateAssets: [AIUpdateAsset]
    let onCheckSelectedUpdates: (Set<AIUpdateAssetKey>) -> Void
    let onUpdateSelected: (Set<AIUpdateAssetKey>) -> Void
    let onCancelUpdateCheck: () -> Void
    @Binding var selection: Set<String>

    private var filteredCLIs: [AIToolRecord] {
        AISectionFilter.filterTools(clis, query: searchText)
    }

    private var selectedRows: [AIUpdateSelectionPlan.SelectedRow] {
        filteredCLIs
            .filter { selection.contains($0.id) }
            .compactMap { tool in
                AIUpdateKeyBuilder.key(for: tool).map {
                    AIUpdateSelectionPlan.SelectedRow(key: $0, displayName: tool.displayName)
                }
            }
    }

    private var selectionPlan: AIUpdateSelectionPlan {
        AIUpdateSelectionPlan(
            selection: selectedRows,
            assets: updateAssets,
            results: updateResults
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = PluginTableLayoutMode(availableWidth: geometry.size.width)
            if clis.isEmpty {
                // No CLI tools discovered. Prefer honest progress/error state
                // over implying nothing is installed.
                if isDiscovering {
                    ContentUnavailableView {
                        Label(L10n.text(.aiOverviewDiscovering), systemImage: "terminal")
                    }
                } else if let discoveryError {
                    ContentUnavailableView {
                        Label(L10n.text(.aiOverviewDiscoveryIssue), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(discoveryError)
                    }
                } else {
                    ContentUnavailableView(
                        L10n.text(.aiCLIEmpty),
                        systemImage: "terminal"
                    )
                }
            } else if filteredCLIs.isEmpty {
                // Source has tools, but the current query matched none.
                ContentUnavailableView(
                    L10n.text(.aiStateNoResults),
                    systemImage: "magnifyingglass"
                )
            } else {
                // Existing tools are shown even while a refresh runs or the last
                // refresh failed; a lightweight banner conveys status without
                // hiding the table.
                VStack(spacing: 0) {
                    AIUpdateActionBar(
                        plan: selectionPlan,
                        isChecking: isCheckingUpdates,
                        onCheckSelected: { onCheckSelectedUpdates(Set(selectionPlan.checkableKeys)) },
                        onUpdateSelected: { onUpdateSelected(Set(selectionPlan.selected.map(\.key))) },
                        onCancel: onCancelUpdateCheck
                    )
                    Divider()
                    refreshBanner
                    if layout == .compact {
                        compactTable
                    } else {
                        regularTable
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var refreshBanner: some View {
        if isDiscovering {
            AIDiscoveryBanner(
                text: L10n.text(.aiOverviewDiscovering),
                systemImage: "arrow.triangle.2.circlepath",
                isError: false
            )
        } else if let discoveryError {
            AIDiscoveryBanner(
                text: discoveryError,
                systemImage: "exclamationmark.triangle",
                isError: true
            )
        }
    }

    private var compactTable: some View {
        Table(filteredCLIs, selection: $selection) {
            TableColumn(L10n.text(.name)) { cliNameCell($0) }
            TableColumn(L10n.text(.aiCLIStatus)) {
                Text(updateStatusText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 96, ideal: 120, max: 140)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private var regularTable: some View {
        Table(filteredCLIs, selection: $selection) {
            TableColumn(L10n.text(.name)) { cliNameCell($0) }
            TableColumn(L10n.version()) {
                Text(currentVersionText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 84, max: 100)
            TableColumn(L10n.text(.aiUpdateLatest)) {
                Text(latestVersionText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 64, ideal: 84, max: 100)
            TableColumn(L10n.text(.aiCLIOwner)) {
                Text(verbatim: L10n.name(for: $0.owner))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 80, ideal: 100, max: 120)
            TableColumn(L10n.text(.aiCLIInstallSource)) {
                Text(installSourceText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 80, ideal: 100, max: 120)
            TableColumn(L10n.text(.aiCLIStatus)) {
                Text(updateStatusText(for: $0))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .width(min: 96, ideal: 120, max: 150)
        }
        .nativeTableDoubleClickReveal(urlAtRow: urlForRow)
    }

    private func cliNameCell(_ tool: AIToolRecord) -> some View {
        VStack(alignment: .leading) {
            Text(tool.displayName)
                .lineLimit(1)
                .truncationMode(.tail)
            Text(executablePath(for: tool))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if !tool.evidence.aliasExecutableURLs.isEmpty {
                // Known aliases resolved to the same executable are surfaced as
                // evidence so the user recognizes the names they invoke (for
                // example trae-cli / trae-agent for traex).
                Text("\(L10n.text(.aiCLIAliases)): \(aliasNames(for: tool))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contextMenu {
            if let url = tool.evidence.executableURL {
                Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
            }
            ForEach(tool.evidence.aliasExecutableURLs, id: \.self) { alias in
                Button("\(L10n.text(.revealFinder)): \(alias.lastPathComponent)") {
                    FinderReveal.reveal(alias)
                }
            }
        }
    }

    private func aliasNames(for tool: AIToolRecord) -> String {
        tool.evidence.aliasExecutableURLs
            .map(\.lastPathComponent)
            .joined(separator: ", ")
    }

    private func executablePath(for tool: AIToolRecord) -> String {
        tool.evidence.executableURL?.path ?? "—"
    }

    /// A short, non-executed label for where the tool was installed, inferred by
    /// the shared `AIInstallSource` classifier from the executable path. Brand
    /// names (Homebrew/npm/pipx) are shown verbatim; local and unknown are
    /// localized.
    private func installSourceText(for tool: AIToolRecord) -> String {
        switch AIInstallSource.classify(executableURL: tool.evidence.executableURL) {
        case .homebrew: return "Homebrew"
        case .npm: return "npm"
        case .pipx: return "pipx"
        case .local: return L10n.text(.aiCLIInstallLocal)
        case .unknown: return "—"
        }
    }

    /// Honest status: an explicit coverage failure wins over version presence so
    /// a partially-covered tool is never shown as simply "not installed".
    private func statusText(for tool: AIToolRecord) -> String {
        if let failure = tool.coverageFailures.sorted(by: { $0.rawValue < $1.rawValue }).first {
            return L10n.name(for: failure)
        }
        return L10n.text(.aiCLIAvailable)
    }

    private func updateResult(for tool: AIToolRecord) -> UpdateCheckResult? {
        guard let key = AIUpdateKeyBuilder.key(for: tool) else { return nil }
        return AIUpdateStatusPresentation.result(for: key, in: updateResults, isChecking: isCheckingUpdates)
    }

    private func updateStatusText(for tool: AIToolRecord) -> String {
        if let result = updateResult(for: tool) {
            return AIUpdateStatusPresentation.statusText(result)
        }
        return statusText(for: tool)
    }

    private func currentVersionText(for tool: AIToolRecord) -> String {
        AIUpdateStatusPresentation.currentVersion(updateResult(for: tool), fallback: tool.evidence.detectedVersion)
    }

    private func latestVersionText(for tool: AIToolRecord) -> String {
        AIUpdateStatusPresentation.latestVersion(updateResult(for: tool))
    }

    private func urlForRow(_ row: Int) -> URL? {
        guard filteredCLIs.indices.contains(row) else { return nil }
        return filteredCLIs[row].evidence.executableURL
    }
}
