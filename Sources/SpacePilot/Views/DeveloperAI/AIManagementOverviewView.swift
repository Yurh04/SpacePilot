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
    let globalSkillCount: Int
    let globalPluginCount: Int
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
                    value: managementProjection.clis.count.formatted()
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
                    L10n.text(.aiOverviewPartialCoverage),
                    value: partialCoverageCount.formatted()
                )
            }
        }
    }
}
