import SpacePilotCore
import SwiftUI

struct OverviewView: View {
    let projection: OverviewProjection?
    let hasSnapshot: Bool
    let latestCleanup: CleanupTransaction?
    let startScan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void
    let openStorage: () -> Void
    let openApplications: () -> Void
    let openHistory: () -> Void

    var body: some View {
        Group {
            if let projection {
                dashboard(projection)
            } else if hasSnapshot {
                ProgressView(L10n.preparingSummary())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.overviewAnalyzeMac), systemImage: "internaldrive")
                } description: {
                    Text(verbatim: L10n.text(.overviewWorksLocally))
                } actions: {
                    Button(L10n.text(.overviewStartScan), action: startScan)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(L10n.overview())
    }

    private func dashboard(_ projection: OverviewProjection) -> some View {
        let state = OverviewDashboardState(
            projection: projection,
            latestCleanup: latestCleanup
        )

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                storageStatus(projection, status: state.capacityStatus)
                quickActions(projection)
                cleanupOpportunities(projection)

                if let recentCleanup = state.recentCleanup {
                    recentCleanupCard(recentCleanup)
                }

                spaceDetails(projection)

                if !projection.coverage.isComplete {
                    coverageWarning
                }
            }
            .frame(maxWidth: 1_200, alignment: .leading)
            .padding(20)
        }
    }

    private func storageStatus(
        _ projection: OverviewProjection,
        status: OverviewDashboardState.CapacityStatus
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: status.icon)
                        .font(.title2)
                        .foregroundStyle(status.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: L10n.text(.overviewStorageStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: status.title)
                            .font(.title3.weight(.semibold))
                    }

                    Spacer()

                    if projection.hasWholeDiskCapacity {
                        Text(ByteCount.string(projection.availableBytes))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }

                if projection.hasWholeDiskCapacity {
                    ProgressView(value: usedFraction(projection))
                        .tint(status.tint)
                        .accessibilityLabel(L10n.text(.overviewInternalDiskUsed))
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    metric(
                        L10n.text(.overviewDiskAvailable),
                        value: projection.hasWholeDiskCapacity
                            ? ByteCount.string(projection.availableBytes)
                            : "—",
                        icon: "internaldrive"
                    )
                    metric(
                        L10n.text(.overviewSafeRecommendations),
                        value: ByteCount.string(projection.reclaimableBytes),
                        icon: "sparkles"
                    )
                    metric(
                        L10n.text(.overviewAnalyzedLocally),
                        value: ByteCount.string(projection.analyzedBytes),
                        icon: "chart.bar.xaxis"
                    )
                }
            }
            .padding(4)
        }
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: value)
                    .font(.headline)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private func quickActions(_ projection: OverviewProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: L10n.text(.overviewQuickActions))
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 175), spacing: 10)],
                spacing: 10
            ) {
                actionButton(
                    L10n.text(.overviewReviewSafeCleanup),
                    icon: "sparkles",
                    prominent: true,
                    disabled: projection.preselectedRecommendations.isEmpty
                ) {
                    reviewCleanup(projection.preselectedRecommendations)
                }
                actionButton(
                    L10n.text(.overviewViewLargestItems),
                    icon: "arrow.down.to.line",
                    action: openStorage
                )
                actionButton(
                    L10n.text(.overviewViewApplications),
                    icon: "square.grid.2x2",
                    action: openApplications
                )
                actionButton(
                    L10n.text(.overviewRescan),
                    icon: "arrow.clockwise",
                    action: startScan
                )
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(action: action) {
                actionButtonLabel(title, icon: icon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(disabled)
        } else {
            Button(action: action) {
                actionButtonLabel(title, icon: icon)
            }
            .buttonStyle(.bordered)
            .disabled(disabled)
        }
    }

    private func actionButtonLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
    }

    private func cleanupOpportunities(_ projection: OverviewProjection) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 0) {
                if projection.preselectedRecommendations.isEmpty {
                    Label(
                        L10n.text(.overviewNoRecommendations),
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                } else {
                    ForEach(Array(projection.preselectedRecommendations.prefix(5).enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        StorageItemRow(item: item)
                            .padding(.vertical, 9)
                    }

                    Divider()
                    HStack {
                        Text(L10n.itemCount(projection.preselectedRecommendations.count))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.reviewCleanup(ByteCount.string(projection.reclaimableBytes))) {
                            reviewCleanup(projection.preselectedRecommendations)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 12)
                }
            }
            .padding(4)
        } label: {
            HStack {
                Label(L10n.text(.overviewTopOpportunities), systemImage: "sparkles")
                Spacer()
                Text(ByteCount.string(projection.reclaimableBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func recentCleanupCard(
        _ recentCleanup: OverviewDashboardState.RecentCleanup
    ) -> some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: L10n.text(.overviewRecentCleanup))
                        .font(.headline)
                    Text(recentCleanup.completedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if let verified = recentCleanup.verifiedFreedBytes {
                        Text(L10n.verifiedSpace(ByteCount.string(verified)))
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(L10n.movedCount(recentCleanup.movedItemCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button(L10n.text(.overviewViewHistory), action: openHistory)
                    .buttonStyle(.bordered)
            }
            .padding(4)
        }
    }

    private func spaceDetails(_ projection: OverviewProjection) -> some View {
        GroupBox {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 300), spacing: 28, alignment: .top)],
                alignment: .leading,
                spacing: 24
            ) {
                diskCapacitySummary(projection)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                AnalyzedCategoryChart(categories: projection.categories)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(4)
        } label: {
            Label(L10n.text(.overviewSpaceDetails), systemImage: "chart.pie")
        }
    }

    private var coverageWarning: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: L10n.text(.overviewLimitedCoverage))
                    .font(.headline)
                Text(verbatim: L10n.text(.overviewLimitedCoverageDescription))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.orange.opacity(0.3))
        }
    }

    @ViewBuilder
    private func diskCapacitySummary(_ projection: OverviewProjection) -> some View {
        if projection.hasWholeDiskCapacity {
            DiskCapacityChart(
                usedBytes: projection.totalUsedBytes,
                availableBytes: projection.availableBytes,
                totalCapacityBytes: projection.totalCapacityBytes
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: L10n.text(.overviewDiskCapacityChart))
                    .font(.headline)
                Label(
                    L10n.text(.overviewDiskCapacityUnavailableDescription),
                    systemImage: "internaldrive"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func usedFraction(_ projection: OverviewProjection) -> Double {
        guard projection.totalCapacityBytes > 0 else { return 0 }
        return min(
            max(Double(projection.totalUsedBytes) / Double(projection.totalCapacityBytes), 0),
            1
        )
    }
}

private extension OverviewDashboardState.CapacityStatus {
    var title: String {
        switch self {
        case .unknown: L10n.text(.overviewStatusUnknown)
        case .healthy: L10n.text(.overviewStatusHealthy)
        case .attention: L10n.text(.overviewStatusAttention)
        case .critical: L10n.text(.overviewStatusCritical)
        }
    }

    var icon: String {
        switch self {
        case .unknown: "questionmark.circle.fill"
        case .healthy: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .unknown: .secondary
        case .healthy: .green
        case .attention: .orange
        case .critical: .red
        }
    }
}
