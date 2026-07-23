import Foundation
import SQLite3
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

    func testSavingLatestSnapshotPrunesOlderPayloadRows() async throws {
        let url = temporaryDatabaseURL()
        let store = try SQLiteIndexStore(url: url)
        try await store.save(snapshot: .fixture(id: UUID(), completedAt: .distantPast))
        let latest = ScanSnapshot.fixture(id: UUID(), completedAt: .now)

        try await store.save(snapshot: latest)

        let metrics = try snapshotMetrics(at: url)
        XCTAssertEqual(metrics.rowCount, 1)
        XCTAssertEqual(metrics.snapshotIDs, [latest.id.uuidString])
        XCTAssertEqual(metrics.totalPayloadBytes, metrics.latestPayloadBytes)
    }

    func testSavingSnapshotTruncatesWriteAheadLog() async throws {
        let url = temporaryDatabaseURL()
        let store = try SQLiteIndexStore(url: url)

        try await store.save(snapshot: .fixture())

        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let walSize = try walURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        XCTAssertEqual(walSize, 0)
    }

    func testPruneFailureRollsBackNewSnapshotAndPreservesPreviousLatest() async throws {
        let url = temporaryDatabaseURL()
        let store = try SQLiteIndexStore(url: url)
        let previous = ScanSnapshot.fixture(id: UUID(), completedAt: .distantPast)
        try await store.save(snapshot: previous)
        try executeSQL(
            """
            CREATE TRIGGER reject_snapshot_prune
            BEFORE DELETE ON snapshots
            BEGIN
                SELECT RAISE(ABORT, 'prune failed');
            END;
            """,
            at: url
        )

        var didThrow = false
        do {
            try await store.save(snapshot: .fixture(id: UUID(), completedAt: .now))
        } catch {
            didThrow = true
        }

        XCTAssertTrue(didThrow)
        let stored = try await store.latestSnapshot()
        XCTAssertEqual(stored?.id, previous.id)
        let metrics = try snapshotMetrics(at: url)
        XCTAssertEqual(metrics.rowCount, 1)
        XCTAssertEqual(metrics.snapshotIDs, [previous.id.uuidString])
    }

    func testIncompleteSessionNeverBecomesLatest() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())

        try await store.begin(sessionID: UUID())

        let stored = try await store.latestSnapshot()
        XCTAssertNil(stored)
    }

    func testPluginDiagnosticsRoundTrip() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let snapshot = ScanSnapshot.fixture(pluginDiagnostics: ["Invalid manifest"])

        try await store.save(snapshot: snapshot)

        let storedSnapshot = try await store.latestSnapshot()
        XCTAssertEqual(storedSnapshot?.pluginDiagnostics, ["Invalid manifest"])
    }

    func testSnapshotWithoutPluginDiagnosticsDecodesAsNil() throws {
        let encodedSnapshot = try JSONEncoder().encode(ScanSnapshot.fixture())
        var oldSnapshot = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedSnapshot) as? [String: Any]
        )
        oldSnapshot.removeValue(forKey: "pluginDiagnostics")
        let oldSnapshotData = try JSONSerialization.data(withJSONObject: oldSnapshot)

        XCTAssertNil(try JSONDecoder().decode(ScanSnapshot.self, from: oldSnapshotData).pluginDiagnostics)
    }

    func testCleanupHistoryRoundTrips() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let sourceURL = URL(fileURLWithPath: "/Users/test/Library/Caches/app/file")
        let transaction = CleanupTransaction(
            planID: UUID(),
            outcomes: [CleanupOutcome(
                candidateID: UUID(),
                status: .movedToTrash,
                resultingURL: URL(fileURLWithPath: "/Users/test/.Trash/file"),
                message: "Moved",
                sourceURL: sourceURL
            )],
            verifiedFreedBytes: 512
        )

        try await store.save(transaction: transaction)

        let history = try await store.cleanupHistory()
        XCTAssertEqual(history.first?.id, transaction.id)
        XCTAssertEqual(history.first?.verifiedFreedBytes, 512)
        XCTAssertEqual(history.first?.outcomes.first?.sourceURL, sourceURL)
    }

    func testCleanupOutcomeDecodesLegacyPayloadWithoutSourceContext() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001",
         "candidateID":"00000000-0000-0000-0000-000000000002",
         "status":"skippedChanged",
         "resultingURL":null,
         "message":"File changed after the scan and was not moved"}
        """.data(using: .utf8)!

        let outcome = try JSONDecoder().decode(CleanupOutcome.self, from: json)

        XCTAssertNil(outcome.sourceURL)
        XCTAssertNil(outcome.sourceAllocatedSize)
        XCTAssertNil(outcome.reason)
    }

    func testInvalidDatabaseIsMovedAsideAndFreshStoreIsCreated() async throws {
        let url = temporaryDatabaseURL()
        try Data("not a sqlite database".utf8).write(to: url)
        try Data("wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("shm".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))

        let store = try SQLiteIndexStore(url: url)

        let stored = try await store.latestSnapshot()
        XCTAssertNil(stored)
        let siblings = try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        )
        let quarantinedDatabase = try XCTUnwrap(
            siblings.first { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") && !$0.lastPathComponent.hasSuffix("-wal") && !$0.lastPathComponent.hasSuffix("-shm") }
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedDatabase.path + "-wal"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantinedDatabase.path + "-shm"))
    }

    func testLockedValidDatabaseThrowsWithoutQuarantiningDatabaseOrSidecars() throws {
        let url = temporaryDatabaseURL()
        try createValidDatabase(at: url, journalMode: "DELETE")

        var lockingDatabase: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &lockingDatabase, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        let database = try XCTUnwrap(lockingDatabase)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "BEGIN EXCLUSIVE;", nil, nil, nil), SQLITE_OK)
        defer { sqlite3_exec(database, "ROLLBACK;", nil, nil, nil) }
        let originalData = try Data(contentsOf: url)
        let originalIdentifier = try fileIdentifier(at: url)

        XCTAssertThrowsError(try SQLiteIndexStore(url: url)) { error in
            guard let storeError = error as? SQLiteStoreError else {
                return XCTFail("Expected SQLiteStoreError, got \(error)")
            }
            XCTAssertTrue([SQLITE_BUSY, SQLITE_LOCKED].contains(storeError.primaryCode))
            XCTAssertFalse(storeError.isConfirmedCorruption)
        }

        XCTAssertEqual(try fileIdentifier(at: url), originalIdentifier)
        XCTAssertEqual(try Data(contentsOf: url), originalData)
        XCTAssertTrue(try corruptSiblings(for: url).isEmpty)
    }

    func testReadOnlyValidDatabaseThrowsWithoutQuarantiningDatabase() throws {
        let url = temporaryDatabaseURL()
        try createValidDatabase(at: url, journalMode: "DELETE", completeSchema: false)
        let originalData = try Data(contentsOf: url)
        let originalIdentifier = try fileIdentifier(at: url)
        let directory = url.deletingLastPathComponent()

        XCTAssertEqual(chmod(url.path, S_IRUSR | S_IRGRP | S_IROTH), 0)
        XCTAssertEqual(chmod(directory.path, S_IRUSR | S_IXUSR), 0)
        defer {
            _ = chmod(directory.path, S_IRWXU)
            _ = chmod(url.path, S_IRUSR | S_IWUSR)
        }

        XCTAssertThrowsError(try SQLiteIndexStore(url: url)) { error in
            guard let storeError = error as? SQLiteStoreError else {
                return XCTFail("Expected SQLiteStoreError, got \(error)")
            }
            XCTAssertTrue([SQLITE_READONLY, SQLITE_CANTOPEN].contains(storeError.primaryCode))
            XCTAssertFalse(storeError.isConfirmedCorruption)
        }

        XCTAssertEqual(try fileIdentifier(at: url), originalIdentifier)
        XCTAssertEqual(try Data(contentsOf: url), originalData)
        XCTAssertTrue(try corruptSiblings(for: url).isEmpty)
    }

    private func temporaryDatabaseURL() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotDatabaseTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "index.sqlite")
    }

    private func createValidDatabase(
        at url: URL,
        journalMode: String = "WAL",
        completeSchema: Bool = true
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not create SQLite test index")
        }
        defer { sqlite3_close(database) }
        let statements = completeSchema
            ? IndexSchema.statements
            : ["CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);"]
        guard sqlite3_exec(database, "PRAGMA journal_mode=\(journalMode);", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        for statement in statements where !statement.hasPrefix("PRAGMA journal_mode=") {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
            }
        }
        guard sqlite3_exec(database, "INSERT INTO metadata(key, value) VALUES ('fixture', 'preserved');", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        _ = sqlite3_wal_checkpoint_v2(database, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    private func fileIdentifier(at url: URL) throws -> AnyHashable {
        try XCTUnwrap(try url.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier as? AnyHashable)
    }

    private func corruptSiblings(for url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url.deletingLastPathComponent(),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(url.lastPathComponent + ".corrupt-") }
    }

    private func snapshotMetrics(at url: URL) throws -> (
        rowCount: Int,
        snapshotIDs: [String],
        totalPayloadBytes: Int64,
        latestPayloadBytes: Int64
    ) {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not inspect SQLite test index")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        let sql = """
        SELECT
            COUNT(*),
            GROUP_CONCAT(s.id, ','),
            COALESCE(SUM(LENGTH(s.payload)), 0),
            COALESCE(MAX(CASE WHEN s.id = m.value THEN LENGTH(s.payload) END), 0)
        FROM snapshots s
        LEFT JOIN metadata m ON m.key = 'latest_complete_snapshot';
        """
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        let ids = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        return (
            rowCount: Int(sqlite3_column_int64(statement, 0)),
            snapshotIDs: ids.isEmpty ? [] : ids.split(separator: ",").map(String.init).sorted(),
            totalPayloadBytes: sqlite3_column_int64(statement, 2),
            latestPayloadBytes: sqlite3_column_int64(statement, 3)
        )
    }

    private func executeSQL(_ sql: String, at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not modify SQLite test index")
        }
        defer { sqlite3_close(database) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) }
                ?? String(cString: sqlite3_errmsg(database))
            sqlite3_free(errorMessage)
            throw SQLiteStoreError(message: message)
        }
    }
}
