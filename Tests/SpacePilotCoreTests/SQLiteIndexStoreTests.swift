import Foundation
import SQLite3
import XCTest
@testable import SpacePilotCore

final class SQLiteIndexStoreTests: XCTestCase {
    func testSavingSnapshotBuildsQueryableOwnershipGraph() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let applicationID = UUID()
        let aiApplicationID = UUID()
        let cacheItemID = UUID()
        let developerItemID = UUID()
        let skillID = UUID()
        let cacheItem = ScannedItem(
            id: cacheItemID,
            url: URL(
                filePath: "/Users/test/Library/Caches/com.example.Editor",
                directoryHint: .isDirectory
            ),
            logicalSize: 600,
            allocatedSize: 512,
            category: .cache,
            risk: .safe,
            explanation: "Application cache"
        )
        let developerItem = ScannedItem(
            id: developerItemID,
            url: URL(
                filePath: "/Users/test/Library/Developer/CoreSimulator",
                directoryHint: .isDirectory
            ),
            logicalSize: 2_048,
            allocatedSize: 2_000,
            category: .developer,
            risk: .sensitive,
            explanation: "Simulator data"
        )
        let association = ArtifactAssociation(
            itemID: cacheItemID,
            applicationID: applicationID,
            evidence: .exactBundleIdentifier,
            confidence: .high,
            risk: .safe,
            ownership: .owned
        )
        let application = ApplicationRecord(
            id: applicationID,
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            version: "1",
            url: URL(
                filePath: "/Applications/Editor.app",
                directoryHint: .isDirectory
            ),
            executableURL: nil,
            allocatedSize: 4_096,
            associations: [association]
        )
        let skill = SkillRecord.fixture(id: skillID, allocatedSize: 128)
        let aiApplication = AIApplicationRecord.fixture(
            id: aiApplicationID,
            name: "Codex",
            itemIDs: [cacheItemID],
            skillIDs: [skillID]
        )
        let snapshot = ScanSnapshot(
            completedAt: Date(timeIntervalSince1970: 1_000),
            volume: nil,
            items: [cacheItem, developerItem],
            applications: [application],
            aiApplications: [aiApplication],
            plugins: [],
            skills: [skill],
            coverage: .complete
        )

        try await store.save(snapshot: snapshot)

        let summary = try await store.storageIndexSummary()
        XCTAssertEqual(summary.ownerCount, 3)
        XCTAssertEqual(summary.resourceCount, 4)
        XCTAssertEqual(summary.ownershipCount, 5)
        XCTAssertEqual(summary.directoryStatCount, 4)
        XCTAssertEqual(summary.allocatedSize, 6_736)
        XCTAssertEqual(summary.lastUpdatedAt, snapshot.completedAt)
        let owners = try await store.storageOwners()
        XCTAssertEqual(
            Set(owners.map(\.id)),
            [
                "app:com.example.editor",
                "ai:codex",
                "developer:tooling"
            ]
        )
        let applicationResources = try await store.resources(
            ownerID: "app:com.example.editor"
        )
        XCTAssertEqual(
            Set(applicationResources.map(\.url.path)),
            [
                "/Applications/Editor.app",
                "/Users/test/Library/Caches/com.example.Editor"
            ]
        )
        let aiResources = try await store.resources(ownerID: "ai:codex")
        XCTAssertEqual(
            Set(aiResources.map(\.url.path)),
            [
                "/Users/test/.agents/skills/fixture-skill",
                "/Users/test/Library/Caches/com.example.Editor"
            ]
        )
    }

    func testNewSnapshotRemovesResourcesNoLongerPresent() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let item = ScannedItem.fixture(allocatedSize: 512)
        let first = ScanSnapshot(
            completedAt: .distantPast,
            volume: nil,
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        try await store.save(snapshot: first)

        try await store.save(snapshot: .fixture())

        let summary = try await store.storageIndexSummary()
        XCTAssertEqual(summary.resourceCount, 0)
        XCTAssertEqual(summary.allocatedSize, 0)
        XCTAssertNil(summary.lastUpdatedAt)
    }

    func testLegacySnapshotDatabaseMigratesToStorageIntelligenceSchema() async throws {
        let url = temporaryDatabaseURL()
        try createLegacyV1Database(at: url)

        let store = try SQLiteIndexStore(url: url)

        XCTAssertEqual(try schemaVersion(at: url), IndexSchema.currentVersion)
        let summary = try await store.storageIndexSummary()
        XCTAssertEqual(summary.resourceCount, 0)
        XCTAssertEqual(try metadataValue(key: "fixture", at: url), "preserved")
    }

    func testExistingSnapshotCanBackfillMissingStorageIndexWithoutRescan() async throws {
        let url = temporaryDatabaseURL()
        let store = try SQLiteIndexStore(url: url)
        let item = ScannedItem.fixture(allocatedSize: 512)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        try await store.save(snapshot: snapshot)
        try executeSQL(
            """
            DELETE FROM storage_ownership;
            DELETE FROM directory_stats;
            DELETE FROM storage_resources;
            DELETE FROM storage_owners;
            DELETE FROM metadata WHERE key = 'latest_storage_snapshot';
            """,
            at: url
        )

        try await store.ensureStorageIndex(snapshot: snapshot)

        let summary = try await store.storageIndexSummary()
        XCTAssertEqual(summary.resourceCount, 1)
        XCTAssertEqual(summary.allocatedSize, 512)
    }

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

    func testOversizedLegacyDatabaseIsDiscardedBeforeOpening() async throws {
        let url = temporaryDatabaseURL()
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(SQLiteIndexStore.maximumDatabaseBytes + 1))
        try handle.close()
        try Data("old wal".utf8).write(to: URL(fileURLWithPath: url.path + "-wal"))
        try Data("old shm".utf8).write(to: URL(fileURLWithPath: url.path + "-shm"))

        let store = try SQLiteIndexStore(url: url)

        let latest = try await store.latestSnapshot()
        XCTAssertNil(latest)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertLessThan(size, SQLiteIndexStore.maximumDatabaseBytes)
    }

    func testStoreRejectsAnUnboundedSnapshot() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let items = (0...SQLiteIndexStore.maximumSnapshotItems).map { index in
            ScannedItem(
                url: URL(fileURLWithPath: "/Users/test/file-\(index)"),
                logicalSize: 1,
                allocatedSize: 1,
                category: .personal,
                risk: .sensitive,
                explanation: "fixture"
            )
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        do {
            try await store.save(snapshot: snapshot)
            XCTFail("Expected oversized snapshot to be rejected")
        } catch let error as SQLiteStoreError {
            XCTAssertTrue(error.message.contains("too many retained items"))
        }
    }

    func testBoundedFileIndexRemainsFarBelowDatabaseSafetyLimit() async throws {
        let url = temporaryDatabaseURL()
        let store = try SQLiteIndexStore(url: url)
        let items = (0..<2_000).map { index in
            ScannedItem(
                url: URL(fileURLWithPath: "/Users/test/Documents/file-\(index)"),
                logicalSize: 4_096,
                allocatedSize: 4_096,
                category: .personal,
                risk: .sensitive,
                explanation: "Large-file index representative"
            )
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        try await store.save(snapshot: snapshot)

        let summary = try await store.storageIndexSummary()
        XCTAssertEqual(summary.resourceCount, 2_000)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertLessThan(bytes, 16 * 1_024 * 1_024)
    }

    func testDirectoryCacheInvalidatesIndexedAncestorForChangedChild() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let directory = URL(
            filePath: "/Users/test/.codex/sessions",
            directoryHint: .isDirectory
        )
        let item = ScannedItem(
            url: directory,
            logicalSize: 1_024,
            allocatedSize: 1_000,
            category: .conversation,
            risk: .sensitive,
            explanation: "Conversation aggregate"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        try await store.save(snapshot: snapshot)
        let initialStat = try await store.cachedDirectoryStat(at: directory)
        XCTAssertEqual(
            initialStat?.totalAllocatedSize,
            1_000
        )

        try await store.markDirectoryStatsDirty(changedPaths: [
            directory.appending(path: "new-session.jsonl")
        ])

        let dirtyStat = try await store.cachedDirectoryStat(at: directory)
        XCTAssertNil(dirtyStat)
        try await store.save(snapshot: snapshot)
        let refreshedStat = try await store.cachedDirectoryStat(at: directory)
        XCTAssertNotNil(refreshedStat)
    }

    func testOpeningStoreInvalidatesLegacyDirectorySizeCaches() async throws {
        let url = temporaryDatabaseURL()
        let directory = URL(
            filePath: "/Users/test/anaconda3",
            directoryHint: .isDirectory
        )
        do {
            let store = try SQLiteIndexStore(url: url)
            let item = ScannedItem(
                url: directory,
                logicalSize: 2_000,
                allocatedSize: 2_000,
                category: .developer,
                risk: .sensitive,
                explanation: "Legacy size"
            )
            try await store.save(snapshot: ScanSnapshot(
                completedAt: .now,
                volume: nil,
                items: [item],
                applications: [],
                aiApplications: [],
                plugins: [],
                skills: [],
                coverage: .complete
            ))
            let initialStat = try await store.cachedDirectoryStat(at: directory)
            XCTAssertNotNil(initialStat)
        }
        try executeSQL(
            "DELETE FROM metadata WHERE key = 'directory_size_algorithm';",
            at: url
        )

        let reopened = try SQLiteIndexStore(url: url)

        let invalidatedStat = try await reopened.cachedDirectoryStat(
            at: directory
        )
        XCTAssertNil(invalidatedStat)
        XCTAssertEqual(
            try metadataValue(key: "directory_size_algorithm", at: url),
            "2"
        )
    }

    func testFileSystemEventCursorRoundTripsByVolume() async throws {
        let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
        let cursor = FileSystemEventCursor(
            volumeID: "volume-fixture",
            lastEventID: 42,
            lastReconciledAt: Date(timeIntervalSince1970: 1_234)
        )

        try await store.save(fileSystemEventCursor: cursor)

        let stored = try await store.fileSystemEventCursor(
            volumeID: "volume-fixture"
        )
        let missing = try await store.fileSystemEventCursor(
            volumeID: "other-volume"
        )
        XCTAssertEqual(stored, cursor)
        XCTAssertNil(missing)
    }

    func testFileSystemEventCursorNeverRegresses() async throws {
        let tree = try TemporaryTree(files: [:])
        let store = try SQLiteIndexStore(
            url: tree.url.appending(path: "index.sqlite")
        )
        let newerDate = Date(timeIntervalSince1970: 200)
        let olderDate = Date(timeIntervalSince1970: 100)

        try await store.save(fileSystemEventCursor: .init(
            volumeID: "volume",
            lastEventID: 200,
            lastReconciledAt: newerDate
        ))
        try await store.save(fileSystemEventCursor: .init(
            volumeID: "volume",
            lastEventID: 100,
            lastReconciledAt: olderDate
        ))

        let cursor = try await store.fileSystemEventCursor(
            volumeID: "volume"
        )
        XCTAssertEqual(cursor?.lastEventID, 200)
        XCTAssertEqual(cursor?.lastReconciledAt, newerDate)
    }

    func testApplicationIdentityCacheRebindsCurrentApplicationIDAndInvalidates() async throws {
        let tree = try TemporaryTree(files: [
            "Example.app/Contents/Info.plist": 16
        ])
        let store = try SQLiteIndexStore(
            url: tree.url.appending(path: "index.sqlite")
        )
        let firstApplication = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            url: tree.url.appending(
                path: "Example.app",
                directoryHint: .isDirectory
            ),
            executableURL: nil,
            allocatedSize: 1_024
        )
        let identity = ApplicationIdentity(
            applicationID: firstApplication.id,
            mainBundleIdentifier: "com.example.app",
            componentBundleIdentifiers: ["com.example.helper"],
            teamIdentifier: "TEAM",
            applicationGroups: ["TEAM.shared"]
        )
        try await store.save(
            applicationIdentity: identity,
            for: firstApplication
        )
        let currentApplication = ApplicationRecord(
            name: firstApplication.name,
            bundleIdentifier: firstApplication.bundleIdentifier,
            version: firstApplication.version,
            url: firstApplication.url,
            executableURL: nil,
            allocatedSize: firstApplication.allocatedSize
        )

        let cached = try await store.cachedApplicationIdentity(
            for: currentApplication
        )

        XCTAssertEqual(cached?.applicationID, currentApplication.id)
        XCTAssertEqual(cached?.teamIdentifier, "TEAM")
        try await store.markDirectoryStatsDirty(changedPaths: [
            firstApplication.url.appending(path: "Contents/new-helper")
        ])
        let invalidatedIdentity = try await store.cachedApplicationIdentity(
            for: currentApplication
        )
        XCTAssertNil(invalidatedIdentity)
    }

    func testAIApplicationCacheInvalidatesWhenAChildChanges() async throws {
        let tree = try TemporaryTree(files: [
            ".codex/sessions/one.jsonl": 32
        ])
        let store = try SQLiteIndexStore(
            url: tree.url.appending(path: "index.sqlite")
        )
        let root = tree.url.appending(
            path: ".codex",
            directoryHint: .isDirectory
        )
        let item = ScannedItem(
            url: root.appending(path: "sessions"),
            logicalSize: 32,
            allocatedSize: 4_096,
            category: .conversation,
            risk: .sensitive,
            explanation: "Cached conversation aggregate"
        )
        let result = AIApplicationScanResult(
            application: AIApplicationRecord(
                name: "Codex",
                bundleIdentifier: "com.openai.codex",
                applicationURL: nil,
                rootURLs: [root],
                itemIDs: [item.id],
                pluginIDs: [],
                skillIDs: [],
                applicationAllocatedSize: 0,
                supportLevel: .deep
            ),
            items: [item]
        )
        try await store.save(
            aiApplicationScan: result,
            key: "codex-v1",
            root: root
        )

        let cached = try await store.cachedAIApplicationScan(
            key: "codex-v1",
            root: root
        )

        XCTAssertEqual(cached?.items.first?.allocatedSize, 4_096)
        try await store.markDirectoryStatsDirty(changedPaths: [
            root.appending(path: "sessions/two.jsonl")
        ])
        let invalidatedScan = try await store.cachedAIApplicationScan(
            key: "codex-v1",
            root: root
        )
        XCTAssertNil(invalidatedScan)
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

    private func createLegacyV1Database(at url: URL) throws {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not create legacy SQLite test index")
        }
        defer { sqlite3_close(database) }
        let statements = [
            "PRAGMA user_version=1;",
            "CREATE TABLE metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
            "CREATE TABLE scan_sessions (id TEXT PRIMARY KEY, status TEXT NOT NULL, started_at REAL NOT NULL);",
            "CREATE TABLE snapshots (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, allocated_size INTEGER NOT NULL, status TEXT NOT NULL, payload BLOB NOT NULL);",
            "CREATE TABLE cleanup_history (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, payload BLOB NOT NULL);",
            "INSERT INTO metadata(key, value) VALUES ('fixture', 'preserved');"
        ]
        for statement in statements {
            guard sqlite3_exec(database, statement, nil, nil, nil) == SQLITE_OK else {
                throw SQLiteStoreError(
                    message: String(cString: sqlite3_errmsg(database))
                )
            }
        }
    }

    private func schemaVersion(at url: URL) throws -> Int {
        try integerQuery("PRAGMA user_version;", at: url)
    }

    private func metadataValue(key: String, at url: URL) throws -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not inspect metadata")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT value FROM metadata WHERE key = ?;",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let value = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: value)
    }

    private func integerQuery(_ sql: String, at url: URL) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw SQLiteStoreError(message: "Could not inspect SQLite integer")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw SQLiteStoreError(message: String(cString: sqlite3_errmsg(database)))
        }
        return Int(sqlite3_column_int64(statement, 0))
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
