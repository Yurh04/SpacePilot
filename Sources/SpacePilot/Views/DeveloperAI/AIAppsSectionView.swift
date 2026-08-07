import SpacePilotCore
import SwiftUI

/// The AI Apps section: keeps the existing deep-scan application list and
/// `AIApplicationDetailView`, and additionally lists applications discovered by
/// the `AIToolRegistry` that do not yet have a deep projection (deduplicated by
/// bundle identifier / standardized application URL, never by display name).
///
/// The sidebar is a single flat `List` with **no** `Section`/header rows so the
/// native double-click adapter's `NSTableView.clickedRow` maps 1:1 to
/// `entries[row]` for both deep and registry-only rows. "Discovered" status is
/// shown with a per-row badge, not a header row. A single unified `String`
/// selection (owned by the persistent `DeveloperAIView` shell) drives the detail
/// pane and is synced back to `model.selectedAIApplicationID`.
struct AIAppsSectionView: View {
    @Bindable var model: AppModel
    let projection: DeveloperAIProjection
    let registryOnlyApplications: [AIApplicationJoin.RegistryOnlyApplication]
    /// Owned by the shell so switching sections never resets the selection.
    @Binding var selectedEntryID: String?
    let isDiscovering: Bool
    let discoveryError: String?

    private var entries: [AIAppsSidebarEntry] {
        AIAppsSidebar.entries(
            deepApplications: projection.applications.map { application in
                AIAppsSidebar.DeepApplication(
                    id: application.id,
                    displayName: application.application.name,
                    subtitle: deepSubtitle(application),
                    revealURL: FinderReveal.applicationURL(for: application.application)
                )
            },
            registryOnlyApplications: registryOnlyApplications
        )
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                emptyState
            } else {
                HSplitView {
                    VStack(spacing: 0) {
                        refreshBanner
                        sidebar
                    }
                    .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: entries.map(\.id), initial: true) { _, _ in
            resolveSelection()
        }
        .onChange(of: selectedEntryID) { _, _ in
            syncSelection()
        }
    }

    /// Distinguishes discovering / discovery-failed / genuinely-empty rather than
    /// showing a bare "no data" when discovery is still in flight or failed.
    @ViewBuilder
    private var emptyState: some View {
        if isDiscovering {
            ContentUnavailableView {
                Label(L10n.text(.aiOverviewDiscovering), systemImage: "sparkles.rectangle.stack")
            }
        } else if let discoveryError {
            ContentUnavailableView {
                Label(L10n.text(.aiOverviewDiscoveryIssue), systemImage: "exclamationmark.triangle")
            } description: {
                Text(discoveryError)
            }
        } else {
            ContentUnavailableView(
                L10n.developerAI(),
                systemImage: "sparkles.rectangle.stack",
                description: Text(verbatim: L10n.noData())
            )
        }
    }

    /// Non-blocking banner shown above the existing list when a refresh is
    /// running or the last one failed; it never hides the existing data.
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

    private var sidebar: some View {
        List(entries, selection: $selectedEntryID) { entry in
            sidebarRow(entry)
                .tag(entry.id)
        }
        .nativeTableDoubleClickReveal { row in
            let entries = entries
            guard entries.indices.contains(row) else { return nil }
            return entries[row].revealURL
        }
    }

    private func sidebarRow(_ entry: AIAppsSidebarEntry) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(entry.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if entry.isDiscovered {
                    Text(L10n.text(.aiAppsDiscovered))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            if let subtitle = entry.subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .contextMenu {
            if let url = entry.revealURL {
                Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let application = selectedDeepApplication {
            AIApplicationDetailView(
                projection: application,
                queryProjection: model.aiQueryProjection,
                isPreparingQuery: model.isPreparingAIQuery,
                pluginDiagnostics: pluginDiagnostics(
                    for: application,
                    from: projection.pluginDiagnostics
                ),
                selectedTab: $model.selectedAIApplicationTab
            )
        } else if let discovered = selectedDiscoveredApplication {
            DiscoveredAIApplicationView(application: discovered)
        } else {
            ContentUnavailableView(
                L10n.text(.aiSelectApplication),
                systemImage: "sparkles.rectangle.stack"
            )
        }
    }

    private var selectedEntry: AIAppsSidebarEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    private var selectedDeepApplication: AIApplicationProjection? {
        guard case .deep(let deepID)? = selectedEntry?.kind else { return nil }
        return projection.applications.first { $0.id == deepID }
    }

    private var selectedDiscoveredApplication: AIApplicationJoin.RegistryOnlyApplication? {
        guard case .registry(let registryID)? = selectedEntry?.kind else { return nil }
        return registryOnlyApplications.first { $0.id == registryID }
    }

    /// Re-resolves the selection when entries change: keeps the current
    /// selection if still valid, otherwise restores the model's existing deep
    /// selection, and only falls back to the first row when neither is valid.
    private func resolveSelection() {
        let resolved = AIAppsSidebar.resolvedSelection(
            entries: entries,
            currentSelectionID: selectedEntryID,
            preferredDeepID: model.selectedAIApplicationID
        )
        if selectedEntryID != resolved {
            selectedEntryID = resolved
        }
        syncSelection()
    }

    /// Mirrors the unified sidebar selection back onto the model's deep-app
    /// selection so the rest of the app (and existing state) stays consistent.
    private func syncSelection() {
        if case .deep(let deepID)? = selectedEntry?.kind {
            if model.selectedAIApplicationID != deepID {
                model.selectedAIApplicationID = deepID
            }
        } else {
            if model.selectedAIApplicationID != nil {
                model.selectedAIApplicationID = nil
            }
        }
    }

    private func deepSubtitle(_ application: AIApplicationProjection) -> String {
        let level = application.application.supportLevel == .deep
            ? L10n.text(.aiDeepAnalysis)
            : L10n.text(.aiBasicFootprint)
        return "\(level) · \(ByteCount.string(application.totalSize))"
    }

    private func pluginDiagnostics(
        for application: AIApplicationProjection,
        from diagnostics: [String]
    ) -> [String] {
        application.application.bundleIdentifier == "com.openai.codex" ? diagnostics : []
    }
}
