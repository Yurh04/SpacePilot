import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class OverviewDashboardStateTests: XCTestCase {
    func testCapacityStatusUsesAvailableSpaceThresholds() {
        XCTAssertEqual(
            state(totalCapacity: 1_000, availableCapacity: 300).capacityStatus,
            .healthy
        )
        XCTAssertEqual(
            state(totalCapacity: 1_000, availableCapacity: 200).capacityStatus,
            .attention
        )
        XCTAssertEqual(
            state(totalCapacity: 1_000, availableCapacity: 100).capacityStatus,
            .critical
        )
    }

    func testCapacityStatusIsUnknownWithoutVerifiedWholeDiskCapacity() {
        let projection = OverviewProjection(snapshot: ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        ))

        XCTAssertEqual(
            OverviewDashboardState(
                projection: projection,
                latestCleanup: nil
            ).capacityStatus,
            .unknown
        )
    }

    func testRecentCleanupCountsOnlyMovedItemsAndKeepsVerifiedSpace() throws {
        let completedAt = Date(timeIntervalSince1970: 123)
        let transaction = CleanupTransaction(
            planID: UUID(),
            completedAt: completedAt,
            outcomes: [
                CleanupOutcome(
                    candidateID: UUID(),
                    status: .movedToTrash,
                    resultingURL: URL(fileURLWithPath: "/Trash/cache"),
                    message: "Moved"
                ),
                CleanupOutcome(
                    candidateID: UUID(),
                    status: .skippedChanged,
                    resultingURL: nil,
                    message: "Changed"
                )
            ],
            verifiedFreedBytes: 512
        )

        let summary = try XCTUnwrap(
            state(
                totalCapacity: 1_000,
                availableCapacity: 300,
                latestCleanup: transaction
            ).recentCleanup
        )

        XCTAssertEqual(summary.completedAt, completedAt)
        XCTAssertEqual(summary.movedItemCount, 1)
        XCTAssertEqual(summary.verifiedFreedBytes, 512)
    }

    @MainActor
    func testCategoryAxisLabelUsesReadableByteUnits() {
        let label = AnalyzedCategoryChart.axisLabel(for: 25_000_000_000)

        XCTAssertTrue(label.contains("GB"), label)
        XCTAssertFalse(label.uppercased().contains("E"), label)
    }

    private func state(
        totalCapacity: Int64,
        availableCapacity: Int64,
        latestCleanup: CleanupTransaction? = nil
    ) -> OverviewDashboardState {
        let projection = OverviewProjection(snapshot: ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Disk",
                totalCapacity: totalCapacity,
                availableCapacity: availableCapacity
            ),
            items: [],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        ))
        return OverviewDashboardState(
            projection: projection,
            latestCleanup: latestCleanup
        )
    }
}
