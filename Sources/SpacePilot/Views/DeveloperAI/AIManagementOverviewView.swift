import SpacePilotCore
import SwiftUI

/// Read-only summary of AI-tool discovery: counts of discovered AI apps, CLI
/// tools, globally indexed skills/plugins, and partial-coverage counts. It shows
/// discovery progress and any discovery error, but never reuses or overwrites
/// the main scan error surface.
struct AIManagementOverviewView: View {
    let managementProjection: AIManagementProjection
    /// The union count of deep + registry-only AI applications, so a deep
    /// application is never shown as 0 while registry discovery is in flight and
    /// a tool present in both sources is not double counted.
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
        List {
            if isDiscovering {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(L10n.text(.aiOverviewDiscovering))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let discoveryError {
                Section {
                    Label(discoveryError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } header: {
                    Text(L10n.text(.aiOverviewDiscoveryIssue))
                }
            }
            Section {
                HStack {
                    Button(L10n.text(.aiUpdateCheckNow)) { onCheckUpdates() }
                        .disabled(isCheckingUpdates)
                    if isCheckingUpdates {
                        Button(L10n.text(.aiUpdateCancel)) { onCancelUpdateCheck() }
                    }
                }
                if isCheckingUpdates {
                    Label(L10n.text(.aiUpdateStatusChecking), systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                }
                if let updateError {
                    Label(updateError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                LabeledContent(
                    L10n.text(.aiUpdateSummaryAvailable),
                    value: updateSummary.updateAvailableCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiUpdateSummaryUpToDate),
                    value: updateSummary.upToDateCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiUpdateSummaryUnknown),
                    value: updateSummary.unknownCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiUpdateSummaryFailed),
                    value: updateSummary.failedCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiUpdateSummaryUnsupported),
                    value: updateSummary.unsupportedCount.formatted()
                )
            } header: {
                Text(L10n.text(.aiUpdateSection))
            } footer: {
                Text(L10n.text(.aiUpdateReadOnlyFooter))
            }
            Section {
                LabeledContent(
                    L10n.text(.aiOverviewApps),
                    value: appCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiOverviewCLIs),
                    value: cliCount.formatted()
                )
                LabeledContent(
                    L10n.skills(),
                    value: globalSkillCount.formatted()
                )
                LabeledContent(
                    L10n.plugins(),
                    value: globalPluginCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiSectionMCP),
                    value: mcpCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiAgentHooks),
                    value: hookCount.formatted()
                )
                LabeledContent(
                    L10n.text(.aiOverviewPartialCoverage),
                    value: partialCoverageCount.formatted()
                )
            }
            if !healthFindings.isEmpty {
                Section {
                    ForEach(healthFindings) { finding in
                        LabeledContent {
                            Text(healthValue(finding))
                                .foregroundStyle(finding.severity == .warning ? .orange : .secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        } label: {
                            Text(healthLabel(finding.kind))
                        }
                    }
                } header: {
                    Text(L10n.text(.aiHealthSection))
                }
            }
            if duplication.duplicatedEntityCount > 0 {
                Section {
                    // Reports the *reclaimable* size (all copies but one), not
                    // the combined size of every copy: keeping one copy is
                    // always required, so the combined figure would overstate
                    // what can actually be freed.
                    LabeledContent(
                        L10n.text(.aiDuplicateStorage),
                        value: L10n.duplicateSummary(
                            entities: duplication.duplicatedEntityCount,
                            reclaimable: ByteCount.string(duplication.totalReclaimable)
                        )
                    )
                    ForEach(duplication.groups.prefix(5)) { group in
                        LabeledContent(group.name) {
                            Text(verbatim: L10n.duplicateCopies(group.copyCount))
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L10n.text(.aiDuplicateStorage))
                }
            }
        }
    }
}
