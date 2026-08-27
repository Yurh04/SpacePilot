import SpacePilotCore
import SwiftUI

/// The AI Agents section. Unifies every piece of evidence that shares a stable
/// `definitionID` into a single Agent (an app bundle and a CLI for the same
/// definition collapse into one row with multiple form factors) and splits them
/// by fixed `locality`: **Local Agents** on top, **Remote Agents** below.
///
/// The sidebar is TWO flat `List`s (one per locality) — never a single list with
/// `Section` header rows — so each list's native double-click adapter maps
/// `NSTableView.clickedRow` 1:1 to that list's `entries[row]`. A single unified
/// `String` selection (the Agent's `definitionID`, owned by the persistent
/// `DeveloperAIView` shell) drives the detail pane. There is no per-cell
/// `TapGesture`: text/whitespace click selects, double-click reveals in Finder.
///
/// Each local Agent's detail pane always shows four modules — Overview, Data &
/// Storage, Plugins, Skills — auto-detected from Core discovery. Remote Agents
/// honestly report modules that do not apply as "Not applicable"; local Agents
/// keep every module even when it currently has zero items.
struct AIAgentsSectionView: View {
    let projection: AIAgentProjection
    let skills: [SkillRecord]
    let plugins: [PluginRecord]
    let storageSizesByPath: [String: Int64]
    /// Owned by the shell so switching sections never resets the selection.
    @Binding var selectedEntryID: String?
    let isDiscovering: Bool
    let discoveryError: String?

    private var localAgents: [AIAgentEntry] { projection.localAgents }
    private var remoteAgents: [AIAgentEntry] { projection.remoteAgents }
    private var allAgents: [AIAgentEntry] { localAgents + remoteAgents }

    var body: some View {
        Group {
            if allAgents.isEmpty {
                emptyState
            } else {
                HSplitView {
                    sidebar
                        .frame(minWidth: 200, idealWidth: 230, maxWidth: 280)
                    detail
                        .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onChange(of: allAgents.map(\.id), initial: true) { _, _ in
            resolveSelection()
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

    // MARK: - Sidebar (two lists: local top, remote bottom)

    private var sidebar: some View {
        VStack(spacing: 0) {
            refreshBanner
            localSection
            Divider()
            remoteSection
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

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader(L10n.text(.aiAgentsLocal))
            if localAgents.isEmpty {
                emptySidebarNote(L10n.text(.aiAgentsLocalEmpty))
            } else {
                List(localAgents, selection: $selectedEntryID) { agent in
                    agentRow(agent).tag(agent.id)
                }
                .nativeTableDoubleClickReveal { row in
                    let agents = localAgents
                    guard agents.indices.contains(row) else { return nil }
                    return revealURL(for: agents[row])
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader(L10n.text(.aiAgentsRemote))
            if remoteAgents.isEmpty {
                emptySidebarNote(L10n.text(.aiAgentsRemoteEmpty))
            } else {
                List(remoteAgents, selection: $selectedEntryID) { agent in
                    agentRow(agent).tag(agent.id)
                }
                .nativeTableDoubleClickReveal { row in
                    let agents = remoteAgents
                    guard agents.indices.contains(row) else { return nil }
                    return revealURL(for: agents[row])
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func sidebarHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
    }

    private func emptySidebarNote(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }

    private func agentRow(_ agent: AIAgentEntry) -> some View {
        HStack(spacing: 8) {
            AgentIcon(descriptor: agent.icon, size: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(agent.displayName)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle = subtitle(for: agent) {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .contextMenu {
            if let url = revealURL(for: agent) {
                Button(L10n.text(.revealFinder)) { FinderReveal.reveal(url) }
            }
        }
    }

    private func subtitle(for agent: AIAgentEntry) -> String? {
        let forms = formFactorLabels(agent.formFactors)
        guard !forms.isEmpty else { return nil }
        return forms.joined(separator: " · ")
    }

    private func formFactorLabels(_ formFactors: Set<AIAgentFormFactor>) -> [String] {
        var labels: [String] = []
        if formFactors.contains(.application) { labels.append(L10n.text(.aiAgentFormApp)) }
        if formFactors.contains(.cli) { labels.append(L10n.text(.aiAgentFormCLI)) }
        if formFactors.contains(.cloud) { labels.append(L10n.text(.aiAgentFormCloud)) }
        return labels
    }

    private func revealURL(for agent: AIAgentEntry) -> URL? {
        agent.applicationURL ?? agent.executableURL
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let agent = selectedAgent {
            AIAgentDetailView(
                detail: AIAgentDetailProjection(
                    agent: agent,
                    skills: skills,
                    plugins: plugins,
                    storageSizesByPath: storageSizesByPath
                ),
                revealURL: revealURL(for: agent),
                formFactorLabels: formFactorLabels(agent.formFactors)
            )
        } else {
            ContentUnavailableView(
                L10n.text(.aiAgentsSelect),
                systemImage: "sparkles.rectangle.stack"
            )
        }
    }

    private var selectedAgent: AIAgentEntry? {
        allAgents.first { $0.id == selectedEntryID }
    }

    /// Keeps the current selection when it still resolves to an Agent; otherwise
    /// falls back to the first local Agent, then the first remote Agent, so a
    /// refresh never leaves the pane pointed at a vanished row.
    private func resolveSelection() {
        if let selectedEntryID, allAgents.contains(where: { $0.id == selectedEntryID }) {
            return
        }
        let fallback = localAgents.first?.id ?? remoteAgents.first?.id
        if selectedEntryID != fallback {
            selectedEntryID = fallback
        }
    }
}
