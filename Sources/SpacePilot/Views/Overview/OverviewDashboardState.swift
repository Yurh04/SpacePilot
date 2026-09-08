import Foundation
import SpacePilotCore

struct OverviewDashboardState: Equatable {
    enum CapacityStatus: Equatable {
        case unknown
        case healthy
        case attention
        case critical
    }

    struct RecentCleanup: Equatable {
        let completedAt: Date
        let movedItemCount: Int
        let verifiedFreedBytes: Int64?
    }

    struct RecentStorageChanges: Equatable {
        let addedBytes: Int64
        let grownBytes: Int64
        let releasedBytes: Int64
        let safeToCleanBytes: Int64
        let availableCapacityDelta: Int64?
        let hasCoverageGap: Bool
    }

    let capacityStatus: CapacityStatus
    let recentCleanup: RecentCleanup?
    let recentStorageChanges: RecentStorageChanges?

    init(
        projection: OverviewProjection,
        latestCleanup: CleanupTransaction?,
        changeHistory: StorageChangeHistory = StorageChangeHistory(),
        now: Date = .now
    ) {
        if projection.hasWholeDiskCapacity,
           projection.totalCapacityBytes > 0 {
            let availableFraction = Double(projection.availableBytes)
                / Double(projection.totalCapacityBytes)
            if availableFraction <= 0.1 {
                capacityStatus = .critical
            } else if availableFraction <= 0.2 {
                capacityStatus = .attention
            } else {
                capacityStatus = .healthy
            }
        } else {
            capacityStatus = .unknown
        }

        recentCleanup = latestCleanup.map { transaction in
            RecentCleanup(
                completedAt: transaction.completedAt,
                movedItemCount: transaction.outcomes.filter {
                    $0.status == .movedToTrash
                }.count,
                verifiedFreedBytes: transaction.verifiedFreedBytes
            )
        }

        if changeHistory.baselineEstablishedAt != nil || !changeHistory.entries.isEmpty {
            let allChanges = StorageChangeProjection(
                history: changeHistory,
                timeRange: .week,
                kindFilter: .all,
                now: now
            )
            let cutoff = StorageChangeTimeRange.week.cutoff(relativeTo: now)
            let safeToCleanBytes = changeHistory.entries.lazy
                .filter { $0.observedAt >= cutoff && $0.isSafeToClean }
                .reduce(Int64(0)) { $0 + $1.afterBytes }
            recentStorageChanges = RecentStorageChanges(
                addedBytes: allChanges.addedBytes,
                grownBytes: allChanges.grownBytes,
                releasedBytes: allChanges.releasedBytes,
                safeToCleanBytes: safeToCleanBytes,
                availableCapacityDelta: allChanges.availableCapacityDelta,
                hasCoverageGap: allChanges.hasCoverageGap
            )
        } else {
            recentStorageChanges = nil
        }
    }
}
