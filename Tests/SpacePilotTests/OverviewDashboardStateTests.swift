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

    func testRecentStorageChangesSummarizeSevenDaysAndSafeItems() throws {
        let now = Date(timeIntervalSince1970: 10 * 24 * 60 * 60)
        let safeItem = StorageChangeEntry(
            url: URL(fileURLWithPath: "/Library/Caches/safe"),
            kind: .added,
            beforeBytes: 0,
            afterBytes: 200,
            startedAt: now.addingTimeInterval(-60),
            observedAt: now.addingTimeInterval(-60),
            risk: .safe
        )
        let sensitiveItem = StorageChangeEntry(
            url: URL(fileURLWithPath: "/Documents/data"),
            kind: .grown,
            beforeBytes: 100,
            afterBytes: 400,
            startedAt: now.addingTimeInterval(-120),
            observedAt: now.addingTimeInterval(-120),
            risk: .sensitive
        )
        let oldItem = StorageChangeEntry(
            url: URL(fileURLWithPath: "/old"),
            kind: .deleted,
            beforeBytes: 900,
            afterBytes: 0,
            startedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            observedAt: now.addingTimeInterval(-8 * 24 * 60 * 60),
            risk: .safe
        )
        let dashboard = OverviewDashboardState(
            projection: projection(totalCapacity: 1_000, availableCapacity: 300),
            latestCleanup: nil,
            changeHistory: StorageChangeHistory(
                entries: [safeItem, sensitiveItem, oldItem],
                baselineEstablishedAt: now.addingTimeInterval(-9 * 24 * 60 * 60)
            ),
            now: now
        )

        let summary = try XCTUnwrap(dashboard.recentStorageChanges)
        XCTAssertEqual(summary.addedBytes, 200)
        XCTAssertEqual(summary.grownBytes, 300)
        XCTAssertEqual(summary.releasedBytes, 0)
        XCTAssertEqual(summary.safeToCleanBytes, 200)
    }

    @MainActor
    func testCategorySizeLabelUsesReadableByteUnits() {
        let label = AnalyzedCategoryChart.sizeLabel(for: 25_000_000_000)

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

    private func projection(
        totalCapacity: Int64,
        availableCapacity: Int64
    ) -> OverviewProjection {
        OverviewProjection(snapshot: ScanSnapshot(
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
    }
}
