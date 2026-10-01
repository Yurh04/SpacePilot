import SpacePilotCore
import SwiftUI

/// Read-only summary of AI-tool discovery: counts of discovered AI apps, CLI
/// tools, globally indexed skills/plugins, and partial-coverage counts. It shows
/// discovery progress and any discovery error, but never reuses or overwrites
/// the main scan error surface.
struct AIManagementOverviewView: View {
    let agents: [AIAgentEntry]
    let onSelectAgent: (String) -> Void
    let managementProjection: AIManagementProjection
    /// Same family-merged Agent count as the sidebar and cards, including CLI-only Agents.
    let appCount: Int
    /// The count of CLI tools shown in the CLI Tools list. Passed in (rather than
    /// read from `managementProjection.clis`) so the overview total matches the
    /// list exactly: agent-capable CLIs like Codex/Claude live under AI Agents and
    /// are excluded from both.
    let cliCount: Int
    let globalSkillCount: Int
    let globalPluginCount: Int
    /// Skills whose content is stored in more than one physical location.
    let duplication: SkillDuplicationAnalyzer.Result
    /// Health findings (duplicate storage, large footprints, externally-driven
    /// hooks), summarised for the overview. Empty hides the section entirely.
    let healthFindings: [AIHealthFinding]
    let mcpCount: Int
    let hookCount: Int
    let isDiscovering: Bool
    let discoveryError: String?
    let updateSummary: UpdateCheckSummary
    let isCheckingUpdates: Bool
    let updateError: String?
    let onCheckUpdates: () -> Void
    let onCancelUpdateCheck: () -> Void

    private var partialCoverageCount: Int {
        managementProjection.recordsWithCoverageFailures.count
    }

    private func healthLabel(_ kind: AIHealthFinding.Kind) -> String {
        switch kind {
        case .duplicateStorage: L10n.text(.aiHealthDuplicate)
        case .largeFootprint: L10n.text(.aiHealthLargeFootprint)
        case .symlinkDependency: L10n.text(.aiHealthSymlink)
        case .unreferencedSkill: L10n.text(.aiHealthUnreferenced)
        }
    }

    /// Composes the human-readable value for a finding from its factual fields.
    /// Wording lives here (the view layer) while the Core finding stays a pure,
    /// non-localized token set.
    private func healthValue(_ finding: AIHealthFinding) -> String {
        switch finding.kind {
        case .duplicateStorage:
            return L10n.duplicateSummary(
                entities: Int(finding.subject) ?? 0,
                reclaimable: ByteCount.string(finding.byteCount)
            )
        case .largeFootprint:
            return "\(finding.subject) · \(ByteCount.string(finding.byteCount))"
        case .symlinkDependency:
            // subject is a count; the row's severity colour already distinguishes
            // a broken-link warning from a live-link note.
            return finding.subject
        case .unreferencedSkill:
            // subject is a count; byteCount is the reclaimable size of dead copies.
            return "\(finding.subject) · \(ByteCount.string(finding.byteCount))"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AIWorkspaceLayout.sectionSpacing) {
                AIWorkspaceHeader(
                    title: L10n.developerAI(),
                    systemImage: "sparkles.rectangle.stack",
                    subtitle: L10n.text(.aiNoContentIndexed),
                    contentPadding: 0
                )
                .padding(.bottom, 4)

                if isDiscovering {
                    AIDiscoveryBanner(text: L10n.text(.aiOverviewDiscovering),
                                      systemImage: "arrow.triangle.2.circlepath", isError: false)
                }
                if let discoveryError {
                    AIDiscoveryBanner(text: discoveryError,
                                      systemImage: "exclamationmark.triangle", isError: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                    AIMetricTile(title: L10n.text(.aiOverviewApps), value: appCount.formatted(),
                                 systemImage: "square.grid.2x2.fill")
                    AIMetricTile(title: L10n.skills(), value: globalSkillCount.formatted(),
                                 systemImage: "sparkles", tint: .purple)
                    AIMetricTile(title: L10n.plugins(), value: globalPluginCount.formatted(),
                                 systemImage: "puzzlepiece.extension.fill", tint: .orange)
                    AIMetricTile(title: L10n.text(.aiOverviewCLIs), value: cliCount.formatted(),
                                 systemImage: "terminal.fill", tint: .teal)
                }

                if !agents.isEmpty {
                    AIWorkspaceCard(title: L10n.text(.aiSectionApps), systemImage: "square.grid.2x2") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                            ForEach(agents) { agent in
                                Button { onSelectAgent(agent.id) } label: {
                                    HStack(spacing: 8) {
                                        AgentIcon(descriptor: agent.icon, size: 28)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(agent.displayName)
                                                .fontWeight(.medium).lineLimit(1).truncationMode(.tail)
                                            Text(agent.locality == .local
                                                 ? L10n.text(.aiAgentsLocal) : L10n.text(.aiAgentsRemote))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .font(.caption).foregroundStyle(.tertiary)
                                    }
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                                    .contentShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                                .interactiveHover(cornerRadius: 10)
                                .help(agent.displayName)
                            }
                        }
                    }
                }

                AIWorkspaceCard(title: L10n.text(.aiGroupCapabilities), systemImage: "square.stack.3d.up") {
                    HStack(spacing: 24) {
                        Label("\(L10n.text(.aiSectionMCP)) · \(mcpCount)", systemImage: "network")
                        Label("\(L10n.text(.aiAgentHooks)) · \(hookCount)", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .foregroundStyle(.secondary)
                    LabeledContent(L10n.text(.aiOverviewPartialCoverage), value: partialCoverageCount.formatted())
                }

                updateCard

                if !healthFindings.isEmpty {
                    AIWorkspaceCard(title: L10n.text(.aiHealthSection), systemImage: "heart.text.clipboard", tint: .orange) {
                        ForEach(healthFindings) { finding in
                            HStack(alignment: .top, spacing: 12) {
                                AIWorkspaceIcon(
                                    systemImage: finding.severity == .warning ? "exclamationmark.triangle" : "info.circle",
                                    tint: finding.severity == .warning ? .orange : .blue, size: 30
                                )
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(healthLabel(finding.kind)).fontWeight(.medium)
                                    Text(healthValue(finding))
                                        .font(.callout).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                if duplication.duplicatedEntityCount > 0 {
                    AIWorkspaceCard(title: L10n.text(.aiDuplicateStorage), systemImage: "square.on.square", tint: .purple) {
                        Text(L10n.duplicateSummary(
                            entities: duplication.duplicatedEntityCount,
                            reclaimable: ByteCount.string(duplication.totalReclaimable)
                        ))
                        .foregroundStyle(.secondary)
                        ForEach(duplication.groups.prefix(5)) { group in
                            HStack(spacing: 12) {
                                AIWorkspaceIcon(systemImage: "folder.fill", size: 28)
                                Text(group.name).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(verbatim: L10n.duplicateCopies(group.copyCount))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(AIWorkspaceLayout.pagePadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background.secondary)
    }

    private var updateCard: some View {
        AIWorkspaceCard(title: L10n.text(.aiUpdateSection), systemImage: "arrow.triangle.2.circlepath", tint: .teal) {
            HStack(spacing: 12) {
                Button(action: onCheckUpdates) {
                    Label(L10n.text(.aiUpdateCheckNow), systemImage: "arrow.clockwise")
                }
                .disabled(isCheckingUpdates)
                if isCheckingUpdates {
                    ProgressView().controlSize(.small)
                    Text(L10n.text(.aiUpdateStatusChecking)).foregroundStyle(.secondary)
                    Button(L10n.text(.aiUpdateCancel), action: onCancelUpdateCheck)
                }
            }
            if let updateError {
                Label(updateError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], alignment: .leading, spacing: 16) {
                updateMetric(L10n.text(.aiUpdateSummaryAvailable), count: updateSummary.updateAvailableCount, color: .blue)
                updateMetric(L10n.text(.aiUpdateSummaryUpToDate), count: updateSummary.upToDateCount, color: .green)
                updateMetric(L10n.text(.aiUpdateSummaryUnknown), count: updateSummary.unknownCount, color: .secondary)
                updateMetric(L10n.text(.aiUpdateSummaryFailed), count: updateSummary.failedCount, color: .orange)
                updateMetric(L10n.text(.aiUpdateSummaryUnsupported), count: updateSummary.unsupportedCount, color: .secondary)
            }
            Text(L10n.text(.aiUpdateReadOnlyFooter)).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func updateMetric(_ title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(count.formatted()).font(.title2.weight(.semibold)).monospacedDigit().foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
