import Foundation
import XCTest
@testable import SpacePilotCore

final class SQLiteIndexStoreTests: XCTestCase {
    func testLatestCompleteSnapshotReplacesOlderSnapshotAtomically() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        try await store.save(snapshot: .fixture(id: UUID(), completedAt: .distantPast))
        let latest = ScanSnapshot.fixture(id: UUID(), completedAt: .now)

        try await store.save(snapshot: latest)

        let stored = try await store.latestSnapshot()
        XCTAssertEqual(stored?.id, latest.id)
    }

    func testIncompleteSessionNeverBecomesLatest() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())

        try await store.begin(sessionID: UUID())

        let stored = try await store.latestSnapshot()
        XCTAssertNil(stored)
    }

    func testCleanupHistoryRoundTrips() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let transaction = CleanupTransaction(
            planID: UUID(),
            outcomes: [CleanupOutcome(
                candidateID: UUID(),
                status: .movedToTrash,
                resultingURL: URL(fileURLWithPath: "/Users/test/.Trash/file"),
                message: "Moved"
            )],
            verifiedFreedBytes: 512
        )

        try await store.save(transaction: transaction)

        let history = try await store.cleanupHistory()
        XCTAssertEqual(history.first?.id, transaction.id)
        XCTAssertEqual(history.first?.verifiedFreedBytes, 512)
    }

    func testInvalidDatabaseIsMovedAsideAndFreshStoreIsCreated() async throws {
        let url = temporaryDatabaseURL()
        try Data("not a sqlite database".utf8).write(to: url)

        let store = try SQLiteIndexStore(url: url)

        let stored = try await store.latestSnapshot()
        XCTAssertNil(stored)
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(siblings.contains { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") })
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotDatabaseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "index.sqlite")
    }
}
