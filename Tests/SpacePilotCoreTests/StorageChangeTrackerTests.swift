import Foundation
import XCTest
@testable import SpacePilotCore

final class StorageChangeTrackerTests: XCTestCase {
    func testDetectorClassifiesAddedGrowthAndDeletion() {
        let date = Date(timeIntervalSince1970: 1_000)
        let megabyte: Int64 = 1_024 * 1_024
        let added = state("/Users/test/new.bin", size: 120 * megabyte, date: date)
        let grownBefore = state("/Users/test/model.bin", size: 100 * megabyte, date: date)
        let grownAfter = state("/Users/test/model.bin", size: 250 * megabyte, date: date.addingTimeInterval(10))
        let deleted = state("/Users/test/old.bin", size: 300 * megabyte, date: date)

        let result = StorageChangeDetector.detect(
            paths: [added.url, grownAfter.url, deleted.url],
            previous: [grownBefore.url.path: grownBefore, deleted.url.path: deleted],
            current: [added.url.path: added, grownAfter.url.path: grownAfter],
            observedAt: date.addingTimeInterval(10)
        )

        XCTAssertEqual(Set(result.entries.map(\.kind)), [.added, .grown, .deleted])
        XCTAssertEqual(result.removedPaths, [deleted.url.path])
    }

    func testDetectorAggregatesSmallChangesByDirectoryAtOneHundredMegabytes() {
        let date = Date(timeIntervalSince1970: 1_000)
        let megabyte: Int64 = 1_024 * 1_024
        let first = state("/Users/test/Downloads/a.bin", size: 60 * megabyte, date: date)
        let second = state("/Users/test/Downloads/b.bin", size: 50 * megabyte, date: date)

        let result = StorageChangeDetector.detect(
            paths: [first.url, second.url],
            previous: [:],
            current: [first.url.path: first, second.url.path: second],
            observedAt: date
        )

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertTrue(result.entries[0].isAggregated)
        XCTAssertEqual(result.entries[0].magnitudeBytes, 110 * megabyte)
        XCTAssertEqual(result.entries[0].url.path, "/Users/test/Downloads")
    }

    func testDetectorCarriesRiskWithoutMarkingAggregatesSafeToClean() {
        let date = Date(timeIntervalSince1970: 1_000)
        let megabyte: Int64 = 1_024 * 1_024
        let individual = state(
            "/Users/test/Library/Caches/large.bin",
            size: 120 * megabyte,
            date: date,
            risk: .safe
        )
        let firstSmall = state(
            "/Users/test/Library/Caches/group/a.bin",
            size: 60 * megabyte,
            date: date,
            risk: .safe
        )
        let secondSmall = state(
            "/Users/test/Library/Caches/group/b.bin",
            size: 50 * megabyte,
            date: date,
            risk: .safe
        )

        let result = StorageChangeDetector.detect(
            paths: [individual.url, firstSmall.url, secondSmall.url],
            previous: [:],
            current: [
                individual.url.path: individual,
                firstSmall.url.path: firstSmall,
                secondSmall.url.path: secondSmall
            ],
            observedAt: date
        )

        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.entries.map(\.risk), [.safe, .safe])
        XCTAssertTrue(result.entries.first { !$0.isAggregated }?.isSafeToClean == true)
        XCTAssertFalse(result.entries.first { $0.isAggregated }?.isSafeToClean == true)
    }

    private func state(
        _ path: String,
        size: Int64,
        date: Date,
        risk: RiskLevel? = nil
    ) -> StorageChangeFileState {
        StorageChangeFileState(
            url: URL(fileURLWithPath: path),
            allocatedSize: size,
            resourceIdentifier: path,
            category: .personal,
            risk: risk,
            observedAt: date,
            lastEventID: 1
        )
    }
}
