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
