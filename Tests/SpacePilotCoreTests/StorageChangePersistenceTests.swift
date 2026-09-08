import Foundation
import XCTest
@testable import SpacePilotCore

final class StorageChangePersistenceTests: XCTestCase {
    func testBaselineAndHistorySurviveStoreReopen() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotStorageChanges-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appending(path: "index.sqlite")
        let date = Date.now.addingTimeInterval(-120)
        let item = ScannedItem(
            url: root.appending(path: "large.bin"),
            logicalSize: 200,
            allocatedSize: 200,
            resourceIdentifier: "large-1",
            category: .personal,
            risk: .sensitive,
            explanation: "test"
        )
        let snapshot = ScanSnapshot(
            completedAt: date,
            volume: .init(url: root, name: "Test", totalCapacity: 1_000, availableCapacity: 400),
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        var store: SQLiteIndexStore? = try SQLiteIndexStore(url: database)
        let created = try await store?.establishStorageChangeBaselineIfNeeded(snapshot: snapshot, eventID: 10)
        XCTAssertEqual(created, true)
        let baselineStates = try await store?.storageChangeStates()
        XCTAssertEqual(baselineStates?.count, 1)
        XCTAssertEqual(baselineStates?[item.url.path]?.risk, .sensitive)

        let event = StorageChangeEntry(
            url: item.url,
            kind: .grown,
            beforeBytes: 200,
            afterBytes: 350,
            startedAt: date,
            observedAt: date.addingTimeInterval(60),
            category: .personal,
            risk: .sensitive
        )
        try await store?.recordStorageChangeUpdate(
            entries: [event],
            states: [.init(
                url: item.url,
                allocatedSize: 350,
                resourceIdentifier: "large-1",
                category: .personal,
                risk: .sensitive,
                observedAt: date.addingTimeInterval(60),
                lastEventID: 11
            )],
            removedPaths: [],
            observation: .init(
                observedAt: date.addingTimeInterval(60),
                totalCapacity: 1_000,
                availableCapacity: 250
            )
        )
        let coalescedEvent = StorageChangeEntry(
            url: item.url,
            kind: .grown,
            beforeBytes: 350,
            afterBytes: 450,
            startedAt: date.addingTimeInterval(60),
            observedAt: date.addingTimeInterval(120),
            category: .personal,
            risk: .sensitive
        )
        try await store?.recordStorageChangeUpdate(
            entries: [coalescedEvent],
            states: [.init(
                url: item.url,
                allocatedSize: 450,
                resourceIdentifier: "large-1",
                category: .personal,
                risk: .sensitive,
                observedAt: date.addingTimeInterval(120),
                lastEventID: 12
            )],
            removedPaths: [],
            observation: .init(
                observedAt: date.addingTimeInterval(120),
                totalCapacity: 1_000,
                availableCapacity: 150
            )
        )
        store = nil

        let reopened = try SQLiteIndexStore(url: database)
        let history = try await reopened.storageChangeHistory(since: date.addingTimeInterval(-1))
        XCTAssertEqual(history.entries.count, 1)
        XCTAssertEqual(history.entries.first?.id, event.id)
        XCTAssertEqual(history.entries.first?.beforeBytes, 200)
        XCTAssertEqual(history.entries.first?.afterBytes, 450)
        XCTAssertEqual(history.entries.first?.risk, .sensitive)
        XCTAssertEqual(history.observations.count, 1)
        XCTAssertEqual(
            history.baselineEstablishedAt?.timeIntervalSince1970 ?? 0,
            date.timeIntervalSince1970,
            accuracy: 0.001
        )
        let reopenedStates = try await reopened.storageChangeStates()
        XCTAssertEqual(reopenedStates[item.url.path]?.allocatedSize, 450)
        XCTAssertEqual(reopenedStates[item.url.path]?.risk, .sensitive)
    }
}
