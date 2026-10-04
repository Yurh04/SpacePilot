import SpacePilotCore
import SwiftUI

struct OverviewView: View {
    let projection: OverviewProjection?
    let hasSnapshot: Bool
    let latestCleanup: CleanupTransaction?
    let changeHistory: StorageChangeHistory
    let startScan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void
    let openStorage: () -> Void
    let openRecentChanges: () -> Void
    let openInstallers: () -> Void
    let openApplications: () -> Void
    let openHistory: () -> Void
    let openDiskAccessSettings: () -> Void

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
            latestCleanup: latestCleanup,
            changeHistory: changeHistory
        )

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                storageStatus(projection, status: state.capacityStatus)
                topActionRow(projection)

                primaryWorkspace(
                    projection,
                    recentCleanup: state.recentCleanup,
                    recentStorageChanges: state.recentStorageChanges
                )
            }
            .frame(maxWidth: 1_200, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func storageStatus(
        _ projection: OverviewProjection,
        status: OverviewDashboardState.CapacityStatus
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
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
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(ByteCount.string(projection.availableBytes))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Text(verbatim: L10n.text(.overviewDiskAvailable))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button(action: startScan) {
                        Label(L10n.text(.overviewRescan), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }

                if projection.hasWholeDiskCapacity {
                    ProgressView(value: usedFraction(projection))
                        .tint(status.tint)
                        .accessibilityLabel(L10n.text(.overviewInternalDiskUsed))
                        .animation(.snappy(duration: 0.25), value: usedFraction(projection))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 0) {
                        metric(
                            L10n.text(.overviewDiskAvailable),
                            value: projection.hasWholeDiskCapacity
                                ? ByteCount.string(projection.availableBytes)
                                : "—",
                            icon: "internaldrive"
                        )
                        Divider()
                        metric(
                            L10n.text(.overviewSafeRecommendations),
                            value: ByteCount.string(projection.reclaimableBytes),
                            icon: "sparkles"
                        )
                        Divider()
                        metric(
                            L10n.text(.overviewAnalyzedLocally),
                            value: ByteCount.string(projection.analyzedBytes),
                            icon: "chart.bar.xaxis"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
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
            }
            .padding(6)
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
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .frame(minWidth: 145, maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func primaryWorkspace(
        _ projection: OverviewProjection,
        recentCleanup: OverviewDashboardState.RecentCleanup?,
        recentStorageChanges: OverviewDashboardState.RecentStorageChanges?
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                summaryWorkspace(
                    projection,
                    recentCleanup: recentCleanup,
                    recentStorageChanges: recentStorageChanges
                )
                    .frame(
                        minWidth: 360,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
                insightsWorkspace(projection)
                    .frame(
                        minWidth: 360,
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .top
                    )
            }
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 16) {
                summaryWorkspace(
                    projection,
                    recentCleanup: recentCleanup,
                    recentStorageChanges: recentStorageChanges
                )
                insightsWorkspace(projection)
            }
        }
    }

    private func summaryWorkspace(
        _ projection: OverviewProjection,
        recentCleanup: OverviewDashboardState.RecentCleanup?,
        recentStorageChanges: OverviewDashboardState.RecentStorageChanges?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            cleanupRecommendationsCard(
                projection,
                recentCleanup: recentCleanup,
                recentStorageChanges: recentStorageChanges
            )

            if let recentStorageChanges {
                recentChangesCard(recentStorageChanges)
            }

            if let recentCleanup {
                recentCleanupCard(recentCleanup)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func cleanupRecommendationsCard(
        _ projection: OverviewProjection,
        recentCleanup: OverviewDashboardState.RecentCleanup?,
        recentStorageChanges: OverviewDashboardState.RecentStorageChanges?
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                cleanupAction(projection)
                Divider()

                HStack {
                    Label(L10n.text(.overviewTopOpportunities), systemImage: "sparkles")
                        .font(.headline)
                    Spacer()
                    Text(ByteCount.string(projection.reclaimableBytes))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if projection.preselectedRecommendations.isEmpty {
                    Label(
                        L10n.text(.overviewNoRecommendations),
                        systemImage: "checkmark.circle"
                    )
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
                } else {
                    let previewLimit = recommendationPreviewLimit(
                        recentCleanup: recentCleanup,
                        recentStorageChanges: recentStorageChanges
                    )
                    ForEach(
                        Array(
                            projection.preselectedRecommendations
                                .prefix(previewLimit)
                                .enumerated()
                        ),
                        id: \.element.id
                    ) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        StorageItemRow(item: item)
                            .padding(.vertical, 6)
                    }

                    Divider()
                    HStack {
                        Text(L10n.itemCount(projection.preselectedRecommendations.count))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(6)
        }
    }

    private func recentChangesCard(
        _ recentStorageChanges: OverviewDashboardState.RecentStorageChanges
    ) -> some View {
        GroupBox {
            recentChangesSummary(recentStorageChanges)
                .padding(6)
        }
    }

    private func recentCleanupCard(
        _ recentCleanup: OverviewDashboardState.RecentCleanup
    ) -> some View {
        GroupBox {
            recentCleanupSummary(recentCleanup)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(6)
        }
    }

    private func cleanupAction(_ projection: OverviewProjection) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: L10n.text(.overviewReviewSafeCleanup))
                    .font(.headline)
                Text(ByteCount.string(projection.reclaimableBytes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button(L10n.reviewCleanup(ByteCount.string(projection.reclaimableBytes))) {
                reviewCleanup(projection.preselectedRecommendations)
            }
            .buttonStyle(.borderedProminent)
            .disabled(projection.preselectedRecommendations.isEmpty)
        }
    }

    private func insightsWorkspace(_ projection: OverviewProjection) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.text(.overviewSpaceDetails), systemImage: "chart.pie")
                    .font(.headline)
                diskCapacitySummary(projection)
                Divider()
                AnalyzedCategoryChart(categories: projection.categories)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(6)
        }
    }

    @ViewBuilder
    private func topActionRow(_ projection: OverviewProjection) -> some View {
        if projection.coverage.isComplete {
            quickLookActions()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    quickLookActions()
                        .frame(minWidth: 620, maxWidth: .infinity)
                    coverageWarning(projection)
                }

                VStack(alignment: .leading, spacing: 12) {
                    quickLookActions()
                    coverageWarning(projection)
                }
            }
        }
    }

    private func quickLookActions() -> some View {
        GroupBox {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text(verbatim: L10n.text(.overviewQuickActions))
                        .font(.headline)
                        .padding(.trailing, 4)
                    quickLookButtons()
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: L10n.text(.overviewQuickActions))
                        .font(.headline)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)
                        ],
                        spacing: 10
                    ) {
                        quickLookButtons()
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func quickLookButtons() -> some View {
        quickLookButton(
            L10n.text(.overviewViewLargestItems),
            icon: "arrow.down.to.line",
            action: openStorage
        )
        quickLookButton(
            L10n.text(.overviewViewRecentChanges),
            icon: "clock.arrow.circlepath",
            action: openRecentChanges
        )
        quickLookButton(
            L10n.text(.overviewViewInstallers),
            icon: "shippingbox.and.arrow.backward.fill",
            action: openInstallers
        )
        quickLookButton(
            L10n.text(.overviewViewApplications),
            icon: "square.grid.2x2",
            action: openApplications
        )
    }

    private func quickLookButton(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        }
        .buttonStyle(.bordered)
    }

    private func recentChangesSummary(
        _ changes: OverviewDashboardState.RecentStorageChanges
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    L10n.text(.overviewRecentChangesSummary),
                    systemImage: "clock.arrow.circlepath"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Button(L10n.text(.overviewViewRecentChanges), action: openRecentChanges)
                    .buttonStyle(.borderless)
            }

            HStack(spacing: 0) {
                recentChangeMetric(
                    L10n.text(.overviewRecentAdded),
                    value: changes.addedBytes,
                    tint: .blue
                )
                recentChangeMetric(
                    L10n.text(.overviewRecentGrown),
                    value: changes.grownBytes,
                    tint: .orange
                )
                recentChangeMetric(
                    L10n.text(.overviewRecentReleased),
                    value: changes.releasedBytes,
                    tint: .green
                )
            }

            HStack(spacing: 12) {
                if changes.safeToCleanBytes > 0 {
                    Label(
                        L10n.recentSafeToClean(
                            ByteCount.string(changes.safeToCleanBytes)
                        ),
                        systemImage: "shield.checkered"
                    )
                }
                Spacer(minLength: 0)
                if let delta = changes.availableCapacityDelta {
                    Text(
                        "\(L10n.text(.storageChangesDiskDelta)): "
                            + signedByteString(delta)
                    )
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func recommendationPreviewLimit(
        recentCleanup: OverviewDashboardState.RecentCleanup?,
        recentStorageChanges: OverviewDashboardState.RecentStorageChanges?
    ) -> Int {
        if recentCleanup != nil && recentStorageChanges != nil { return 2 }
        if recentCleanup != nil || recentStorageChanges != nil { return 3 }
        return 4
    }

    private func recentChangeMetric(
        _ title: String,
        value: Int64,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(ByteCount.string(value))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentCleanupSummary(
        _ recentCleanup: OverviewDashboardState.RecentCleanup
    ) -> some View {
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
    }

    private func coverageWarning(_ projection: OverviewProjection) -> some View {
        HStack(alignment: .center, spacing: 9) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: L10n.text(.overviewLimitedCoverage))
                    .font(.subheadline.weight(.semibold))
                Text(L10n.inaccessibleFolderCount(projection.coverage.deniedPaths.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button(
                L10n.text(.settingsOpenDiskAccess),
                action: openDiskAccessSettings
            )
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .fixedSize(horizontal: true, vertical: false)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.22), lineWidth: 1)
        }
        .help(L10n.text(.overviewLimitedCoverageDescription))
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

    private func signedByteString(_ bytes: Int64) -> String {
        if bytes == 0 { return ByteCount.string(0) }
        return (bytes > 0 ? "+" : "−") + ByteCount.string(abs(bytes))
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
