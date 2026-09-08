import Foundation
import XCTest
@testable import SpacePilotCore

final class StorageChangeHistoryTests: XCTestCase {
    func testProjectionFiltersTimeKindAndSearchAndComputesTotals() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let recentAdded = entry(path: "/Users/test/Downloads/video.mov", kind: .added, before: 0, after: 200, date: now)
        let recentGrowth = entry(path: "/Users/test/Library/model.bin", kind: .grown, before: 100, after: 450, date: now)
        let oldDeletion = entry(path: "/Users/test/old.zip", kind: .deleted, before: 900, after: 0, date: now.addingTimeInterval(-8 * 86_400))
        let history = StorageChangeHistory(entries: [recentAdded, recentGrowth, oldDeletion])

        let projection = StorageChangeProjection(
            history: history,
            timeRange: .week,
            kindFilter: .grown,
            searchText: "model",
            now: now
        )

        XCTAssertEqual(projection.entries.map(\.id), [recentGrowth.id])
        XCTAssertEqual(projection.addedBytes, 0)
        XCTAssertEqual(projection.grownBytes, 350)
        XCTAssertEqual(projection.releasedBytes, 0)
        XCTAssertEqual(projection.trackedNetBytes, 350)
    }

    func testProjectionReportsDiskDeltaAndCoverageGap() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let history = StorageChangeHistory(
            observations: [
                .init(observedAt: now.addingTimeInterval(-3_600), totalCapacity: 1_000, availableCapacity: 600),
                .init(observedAt: now, totalCapacity: 1_000, availableCapacity: 450)
            ],
            coverageGaps: [.init(startedAt: now.addingTimeInterval(-1_800), reason: "events dropped")]
        )

        let projection = StorageChangeProjection(history: history, timeRange: .day, kindFilter: .all, now: now)

        XCTAssertEqual(projection.availableCapacityDelta, -150)
        XCTAssertTrue(projection.hasCoverageGap)
    }

    func testEntryUsesOneHundredMegabyteDisplayThresholdAndOneGigabyteHighlight() {
        XCTAssertEqual(StorageChangeEntry.individualDisplayThreshold, 100 * 1_024 * 1_024)
        let entry = entry(
            path: "/Users/test/large.bin",
            kind: .grown,
            before: 0,
            after: 1_024 * 1_024 * 1_024,
            date: .now
        )
        XCTAssertTrue(entry.isHighlighted)
    }

    func testOnlyCurrentIndividualSafeEntriesAreMarkedSafeToClean() {
        let date = Date.now
        let safe = entry(
            path: "/Users/test/Library/Caches/current.bin",
            kind: .grown,
            before: 100,
            after: 200,
            date: date,
            risk: .safe
        )
        let deleted = entry(
            path: "/Users/test/Library/Caches/deleted.bin",
            kind: .deleted,
            before: 200,
            after: 0,
            date: date,
            risk: .safe
        )
        let aggregated = StorageChangeEntry(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches"),
            kind: .grown,
            beforeBytes: 100,
            afterBytes: 200,
            startedAt: date,
            observedAt: date,
            risk: .safe,
            isAggregated: true
        )
        let unknown = entry(
            path: "/Users/test/Documents/unknown.bin",
            kind: .added,
            before: 0,
            after: 200,
            date: date
        )

        XCTAssertTrue(safe.isSafeToClean)
        XCTAssertFalse(deleted.isSafeToClean)
        XCTAssertFalse(aggregated.isSafeToClean)
        XCTAssertFalse(unknown.isSafeToClean)
    }

    func testSafeOnlyProjectionFiltersBeforeApplyingDisplayLimitAndSummary() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let unsafeEntries = (0..<StorageChangeProjection.itemDisplayLimit).map { index in
            StorageChangeEntry(
                url: URL(fileURLWithPath: "/Users/test/Documents/unsafe-\(index)"),
                kind: .added,
                beforeBytes: 0,
                afterBytes: Int64(1_000 - index) * 1_024 * 1_024,
                startedAt: now,
                observedAt: now,
                risk: .sensitive
            )
        }
        let safe = StorageChangeEntry(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/safe"),
            kind: .added,
            beforeBytes: 0,
            afterBytes: 100 * 1_024 * 1_024,
            startedAt: now,
            observedAt: now,
            risk: .safe
        )

        let projection = StorageChangeProjection(
            history: StorageChangeHistory(entries: unsafeEntries + [safe]),
            timeRange: .day,
            kindFilter: .all,
            safeOnly: true,
            now: now
        )

        XCTAssertEqual(projection.entries, [safe])
        XCTAssertEqual(projection.addedBytes, safe.magnitudeBytes)
    }

    private func entry(
        path: String,
        kind: StorageChangeKind,
        before: Int64,
        after: Int64,
        date: Date,
        risk: RiskLevel? = nil
    ) -> StorageChangeEntry {
        StorageChangeEntry(
            url: URL(fileURLWithPath: path),
            kind: kind,
            beforeBytes: before,
            afterBytes: after,
            startedAt: date,
            observedAt: date,
            risk: risk
        )
    }
}
