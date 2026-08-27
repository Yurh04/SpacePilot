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

    let capacityStatus: CapacityStatus
    let recentCleanup: RecentCleanup?

    init(
        projection: OverviewProjection,
        latestCleanup: CleanupTransaction?
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
    }
}
