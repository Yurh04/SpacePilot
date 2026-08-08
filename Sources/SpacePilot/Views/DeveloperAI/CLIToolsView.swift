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
    @Binding var selection: String?

    private var filteredCLIs: [AIToolRecord] {
        AISectionFilter.filterTools(clis, query: searchText)
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
                Text(statusText(for: $0))
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
                Text($0.evidence.detectedVersion ?? "—")
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
            TableColumn(L10n.text(.aiCLIStatus)) {
                Text(statusText(for: $0))
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
        }
        .contextMenu {
            if let url = tool.evidence.executableURL {
                Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
            }
        }
    }

    private func executablePath(for tool: AIToolRecord) -> String {
        tool.evidence.executableURL?.path ?? "—"
    }

    /// Honest status: an explicit coverage failure wins over version presence so
    /// a partially-covered tool is never shown as simply "not installed".
    private func statusText(for tool: AIToolRecord) -> String {
        if let failure = tool.coverageFailures.sorted(by: { $0.rawValue < $1.rawValue }).first {
            return L10n.name(for: failure)
        }
        return L10n.text(.aiCLIAvailable)
    }

    private func urlForRow(_ row: Int) -> URL? {
        guard filteredCLIs.indices.contains(row) else { return nil }
        return filteredCLIs[row].evidence.executableURL
    }
}
