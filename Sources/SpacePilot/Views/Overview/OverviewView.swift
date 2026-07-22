import SpacePilotCore
import SwiftUI

struct OverviewView: View {
    let projection: OverviewProjection?
    let hasSnapshot: Bool
    let startScan: () -> Void
    let reviewCleanup: ([ScannedItem]) -> Void

    var body: some View {
        Group {
            if let projection {
                List {
                    Section {
                        LabeledContent(L10n.text(.overviewInternalDiskUsed), value: ByteCount.string(projection.totalUsedBytes))
                        LabeledContent(L10n.text(.overviewAnalyzedLocally), value: ByteCount.string(projection.analyzedBytes))
                        LabeledContent(L10n.text(.overviewSafeRecommendations), value: ByteCount.string(projection.reclaimableBytes))
                    } header: {
                        Text(verbatim: L10n.text(.overviewStorageGlance))
                    }

                    Section(L10n.text(.overviewSafeRecommendations)) {
                        if projection.preselectedRecommendations.isEmpty {
                            Text(verbatim: L10n.text(.overviewNoRecommendations))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(projection.preselectedRecommendations.prefix(8)) { item in
                                StorageItemRow(item: item)
                            }
                            Button(L10n.reviewCleanup(ByteCount.string(projection.reclaimableBytes))) {
                                reviewCleanup(projection.preselectedRecommendations)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if !projection.coverage.isComplete {
                        Section(L10n.text(.overviewLimitedCoverage)) {
                            Label(L10n.text(.overviewLimitedCoverageDescription), systemImage: "lock.trianglebadge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(L10n.overview())
            } else if hasSnapshot {
                ProgressView(L10n.preparingSummary())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(L10n.overview())
            } else {
                ContentUnavailableView {
                    Label(L10n.text(.overviewAnalyzeMac), systemImage: "internaldrive")
                } description: {
                    Text(verbatim: L10n.text(.overviewWorksLocally))
                } actions: {
                    Button(L10n.text(.overviewStartScan), action: startScan)
                        .buttonStyle(.borderedProminent)
                }
                .navigationTitle(L10n.overview())
            }
        }
    }
}
