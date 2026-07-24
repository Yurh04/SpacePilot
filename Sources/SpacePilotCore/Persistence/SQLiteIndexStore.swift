import Foundation
import SQLite3

public protocol SnapshotStoring: Sendable {
    func save(snapshot: ScanSnapshot) async throws
    func latestSnapshot() async throws -> ScanSnapshot?
    func save(transaction: CleanupTransaction) async throws
    func cleanupHistory() async throws -> [CleanupTransaction]
}

public actor SQLiteIndexStore: SnapshotStoring {
    static let maximumDatabaseBytes: Int64 = 128 * 1024 * 1024
    static let maximumSnapshotItems = ScanSnapshot.maximumRetainedItems

    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if Self.fileSize(at: url) > Self.maximumDatabaseBytes {
            try Self.removeStoreFiles(at: url)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        self.encoder = encoder
        self.decoder = decoder

        do {
            let candidate = try SQLiteConnection(url: url)
            try Self.installSchema(on: candidate)
            connection = candidate
        } catch let error as SQLiteStoreError where error.isConfirmedCorruption {
            try Self.quarantineCorruptStore(at: url)
            let fresh = try SQLiteConnection(url: url)
            try Self.installSchema(on: fresh)
            connection = fresh
        } catch {
            throw error
        }
    }

    public func begin(sessionID: UUID) throws {
        try connection.statement("INSERT INTO scan_sessions(id, status, started_at) VALUES (?, 'incomplete', ?);") { statement in
            try connection.bind(sessionID.uuidString, to: 1, in: statement)
            try connection.bind(Date().timeIntervalSince1970, to: 2, in: statement)
            try connection.stepDone(statement)
        }
    }

    public func save(snapshot: ScanSnapshot) throws {
        guard snapshot.items.count <= Self.maximumSnapshotItems else {
            throw SQLiteStoreError(
                message: "Snapshot contains too many retained items (\(snapshot.items.count)); "
                    + "the limit is \(Self.maximumSnapshotItems)"
            )
        }
        let payload = try encoder.encode(snapshot)
        let intelligenceGraph = StorageIntelligenceGraph(snapshot: snapshot)
        let allocatedSize = snapshot.items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        try connection.execute("BEGIN IMMEDIATE;")
        do {
            try connection.statement("INSERT OR REPLACE INTO snapshots(id, completed_at, allocated_size, status, payload) VALUES (?, ?, ?, 'complete', ?);") { statement in
                try connection.bind(snapshot.id.uuidString, to: 1, in: statement)
                try connection.bind(snapshot.completedAt.timeIntervalSince1970, to: 2, in: statement)
                try connection.bind(allocatedSize, to: 3, in: statement)
                try connection.bind(payload, to: 4, in: statement)
                try connection.stepDone(statement)
            }
            try connection.statement("INSERT OR REPLACE INTO metadata(key, value) VALUES ('latest_complete_snapshot', ?);") { statement in
                try connection.bind(snapshot.id.uuidString, to: 1, in: statement)
                try connection.stepDone(statement)
            }
            try connection.statement("DELETE FROM snapshots WHERE id <> ?;") { statement in
                try connection.bind(snapshot.id.uuidString, to: 1, in: statement)
                try connection.stepDone(statement)
            }
            try synchronize(
                graph: intelligenceGraph,
                snapshotID: snapshot.id.uuidString
            )
            try connection.execute("COMMIT;")
        } catch {
            try? connection.execute("ROLLBACK;")
            throw error
        }
        try? connection.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    public func latestSnapshot() throws -> ScanSnapshot? {
        try connection.statement("SELECT s.payload FROM snapshots s JOIN metadata m ON m.value = s.id WHERE m.key = 'latest_complete_snapshot' AND s.status = 'complete' LIMIT 1;") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            return try decoder.decode(ScanSnapshot.self, from: connection.blob(at: 0, in: statement))
        }
    }

    public func ensureStorageIndex(snapshot: ScanSnapshot) throws {
        if try metadataValue(for: "latest_storage_snapshot") == snapshot.id.uuidString {
            return
        }
        let graph = StorageIntelligenceGraph(snapshot: snapshot)
        try connection.execute("BEGIN IMMEDIATE;")
        do {
            try synchronize(graph: graph, snapshotID: snapshot.id.uuidString)
            try connection.execute("COMMIT;")
        } catch {
            try? connection.execute("ROLLBACK;")
            throw error
        }
        try? connection.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    }

    public func save(transaction: CleanupTransaction) throws {
        let payload = try encoder.encode(transaction)
        try connection.statement("INSERT OR REPLACE INTO cleanup_history(id, completed_at, payload) VALUES (?, ?, ?);") { statement in
            try connection.bind(transaction.id.uuidString, to: 1, in: statement)
            try connection.bind(transaction.completedAt.timeIntervalSince1970, to: 2, in: statement)
            try connection.bind(payload, to: 3, in: statement)
            try connection.stepDone(statement)
        }
    }

    public func cleanupHistory() throws -> [CleanupTransaction] {
        try connection.statement("SELECT payload FROM cleanup_history ORDER BY completed_at DESC;") { statement in
            var values: [CleanupTransaction] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                values.append(try decoder.decode(CleanupTransaction.self, from: connection.blob(at: 0, in: statement)))
            }
            return values
        }
    }

    public func storageIndexSummary() throws -> StorageIndexSummary {
        try connection.statement(
            """
            SELECT
                (SELECT COUNT(*) FROM storage_owners),
                (SELECT COUNT(*) FROM storage_resources),
                (SELECT COUNT(*) FROM storage_ownership),
                (SELECT COUNT(*) FROM directory_stats),
                (SELECT COALESCE(SUM(allocated_size), 0) FROM storage_resources),
                (SELECT MAX(indexed_at) FROM storage_resources);
            """
        ) { statement in
            guard try connection.step(statement) == SQLITE_ROW else {
                return StorageIndexSummary(
                    ownerCount: 0,
                    resourceCount: 0,
                    ownershipCount: 0,
                    directoryStatCount: 0,
                    allocatedSize: 0,
                    lastUpdatedAt: nil
                )
            }
            let timestamp = sqlite3_column_type(statement, 5) == SQLITE_NULL
                ? nil
                : sqlite3_column_double(statement, 5)
            return StorageIndexSummary(
                ownerCount: Int(sqlite3_column_int64(statement, 0)),
                resourceCount: Int(sqlite3_column_int64(statement, 1)),
                ownershipCount: Int(sqlite3_column_int64(statement, 2)),
                directoryStatCount: Int(sqlite3_column_int64(statement, 3)),
                allocatedSize: sqlite3_column_int64(statement, 4),
                lastUpdatedAt: timestamp.map(Date.init(timeIntervalSince1970:))
            )
        }
    }

    public func storageOwners() throws -> [StorageOwner] {
        try connection.statement(
            """
            SELECT id, type, identifier, display_name
            FROM storage_owners
            ORDER BY type, display_name COLLATE NOCASE, id;
            """
        ) { statement in
            var owners: [StorageOwner] = []
            while try connection.step(statement) == SQLITE_ROW {
                guard let type = StorageOwnerType(
                    rawValue: Self.text(at: 1, in: statement)
                ) else {
                    continue
                }
                owners.append(StorageOwner(
                    id: Self.text(at: 0, in: statement),
                    type: type,
                    identifier: Self.text(at: 2, in: statement),
                    displayName: Self.text(at: 3, in: statement)
                ))
            }
            return owners
        }
    }

    public func resources(ownerID: String) throws -> [IndexedStorageResource] {
        try connection.statement(
            """
            SELECT
                r.id, r.path, r.kind, r.logical_size, r.allocated_size,
                r.modified_at, r.resource_identifier, r.category, r.risk,
                r.state, r.indexed_at
            FROM storage_resources r
            JOIN storage_ownership o ON o.resource_id = r.id
            WHERE o.owner_id = ?
            ORDER BY r.allocated_size DESC, r.path;
            """
        ) { statement in
            try connection.bind(ownerID, to: 1, in: statement)
            var resources: [IndexedStorageResource] = []
            while try connection.step(statement) == SQLITE_ROW {
                guard let kind = IndexedResourceKind(
                    rawValue: Self.text(at: 2, in: statement)
                ), let category = ItemCategory(
                    rawValue: Self.text(at: 7, in: statement)
                ), let risk = RiskLevel(
                    rawValue: Self.text(at: 8, in: statement)
                ), let state = IndexedResourceState(
                    rawValue: Self.text(at: 9, in: statement)
                ) else {
                    continue
                }
                let modifiedTimestamp = sqlite3_column_double(statement, 5)
                let resourceIdentifier = Self.text(at: 6, in: statement)
                resources.append(IndexedStorageResource(
                    id: Self.text(at: 0, in: statement),
                    url: URL(fileURLWithPath: Self.text(at: 1, in: statement)),
                    kind: kind,
                    logicalSize: sqlite3_column_int64(statement, 3),
                    allocatedSize: sqlite3_column_int64(statement, 4),
                    modificationDate: modifiedTimestamp > 0
                        ? Date(timeIntervalSince1970: modifiedTimestamp)
                        : nil,
                    resourceIdentifier: resourceIdentifier.isEmpty
                        ? nil
                        : resourceIdentifier,
                    category: category,
                    risk: risk,
                    state: state,
                    indexedAt: Date(
                        timeIntervalSince1970: sqlite3_column_double(
                            statement,
                            10
                        )
                    )
                ))
            }
            return resources
        }
    }

    public func cachedDirectoryStat(at url: URL) throws -> DirectoryStat? {
        try connection.statement(
            """
            SELECT
                d.resource_id, d.total_logical_size, d.total_allocated_size,
                d.file_count, d.directory_count, d.indexed_at, d.dirty
            FROM directory_stats d
            JOIN storage_resources r ON r.id = d.resource_id
            WHERE r.path = ? AND d.dirty = 0 AND r.state = 'current'
            LIMIT 1;
            """
        ) { statement in
            try connection.bind(
                url.standardizedFileURL.path,
                to: 1,
                in: statement
            )
            guard try connection.step(statement) == SQLITE_ROW else {
                return nil
            }
            let fileCount = sqlite3_column_int64(statement, 3)
            let directoryCount = sqlite3_column_int64(statement, 4)
            return DirectoryStat(
                resourceID: Self.text(at: 0, in: statement),
                totalLogicalSize: sqlite3_column_int64(statement, 1),
                totalAllocatedSize: sqlite3_column_int64(statement, 2),
                fileCount: fileCount >= 0 ? Int(fileCount) : nil,
                directoryCount: directoryCount >= 0
                    ? Int(directoryCount)
                    : nil,
                indexedAt: Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 5)
                ),
                isDirty: sqlite3_column_int64(statement, 6) != 0
            )
        }
    }

    public func markDirectoryStatsDirty(changedPaths: [URL]) throws {
        let paths = Set(changedPaths.map { $0.standardizedFileURL.path })
            .sorted()
        guard !paths.isEmpty else { return }
        try connection.execute("BEGIN IMMEDIATE;")
        do {
            try connection.statement(
                """
                UPDATE directory_stats
                SET dirty = 1
                WHERE resource_id IN (
                    SELECT id FROM storage_resources
                    WHERE path = ?
                       OR ? LIKE path || '/%'
                       OR path LIKE ? || '/%'
                );
                """
            ) { statement in
                for path in paths {
                    for index: Int32 in 1...3 {
                        try connection.bind(path, to: index, in: statement)
                    }
                    try connection.stepDone(statement)
                    try connection.reset(statement)
                }
            }
            try connection.statement(
                """
                UPDATE storage_resources
                SET state = 'dirty'
                WHERE path = ?
                   OR ? LIKE path || '/%'
                   OR path LIKE ? || '/%';
                """
            ) { statement in
                for path in paths {
                    for index: Int32 in 1...3 {
                        try connection.bind(path, to: index, in: statement)
                    }
                    try connection.stepDone(statement)
                    try connection.reset(statement)
                }
            }
            try markScanCachesDirty(paths: paths)
            try connection.execute("COMMIT;")
        } catch {
            try? connection.execute("ROLLBACK;")
            throw error
        }
    }

    public func markAllDirectoryStatsDirty() throws {
        try connection.execute("BEGIN IMMEDIATE;")
        do {
            try connection.execute("UPDATE directory_stats SET dirty = 1;")
            try connection.execute(
                """
                UPDATE storage_resources
                SET state = 'dirty'
                WHERE id IN (SELECT resource_id FROM directory_stats);
                """
            )
            try connection.execute("UPDATE scan_caches SET dirty = 1;")
            try connection.execute("COMMIT;")
        } catch {
            try? connection.execute("ROLLBACK;")
            throw error
        }
    }

    public func save(fileSystemEventCursor cursor: FileSystemEventCursor) throws {
        try connection.statement(
            """
            INSERT INTO fsevent_cursors(
                volume_id, last_event_id, last_reconciled_at
            ) VALUES (?, ?, ?)
            ON CONFLICT(volume_id) DO UPDATE SET
                last_event_id = MAX(
                    fsevent_cursors.last_event_id,
                    excluded.last_event_id
                ),
                last_reconciled_at = CASE
                    WHEN excluded.last_event_id
                        >= fsevent_cursors.last_event_id
                    THEN excluded.last_reconciled_at
                    ELSE fsevent_cursors.last_reconciled_at
                END;
            """
        ) { statement in
            try connection.bind(cursor.volumeID, to: 1, in: statement)
            try connection.bind(cursor.lastEventID, to: 2, in: statement)
            try connection.bind(
                cursor.lastReconciledAt.timeIntervalSince1970,
                to: 3,
                in: statement
            )
            try connection.stepDone(statement)
        }
    }

    public func fileSystemEventCursor(
        volumeID: String
    ) throws -> FileSystemEventCursor? {
        try connection.statement(
            """
            SELECT last_event_id, last_reconciled_at
            FROM fsevent_cursors
            WHERE volume_id = ?
            LIMIT 1;
            """
        ) { statement in
            try connection.bind(volumeID, to: 1, in: statement)
            guard try connection.step(statement) == SQLITE_ROW else {
                return nil
            }
            return FileSystemEventCursor(
                volumeID: volumeID,
                lastEventID: sqlite3_column_int64(statement, 0),
                lastReconciledAt: Date(
                    timeIntervalSince1970: sqlite3_column_double(statement, 1)
                )
            )
        }
    }

    public func cachedApplicationIdentity(
        for application: ApplicationRecord
    ) throws -> ApplicationIdentity? {
        let key = "application-identity:" + application.url.standardizedFileURL.path
        guard let cached: ApplicationIdentity = try cachedScanResult(
            key: key,
            validationToken: ScanCacheValidation.token(for: application)
        ) else {
            return nil
        }
        return ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: cached.mainBundleIdentifier,
            componentBundleIdentifiers: cached.componentBundleIdentifiers,
            teamIdentifier: cached.teamIdentifier,
            applicationGroups: cached.applicationGroups
        )
    }

    public func cachedApplicationInventory(
        at location: URL
    ) throws -> [ApplicationRecord]? {
        try cachedScanResult(
            key: "application-inventory:"
                + location.standardizedFileURL.path,
            validationToken: ScanCacheValidation.applicationInventoryToken(
                at: location
            )
        )
    }

    public func save(
        applicationInventory: [ApplicationRecord],
        at location: URL
    ) throws {
        try saveScanResult(
            applicationInventory,
            key: "application-inventory:"
                + location.standardizedFileURL.path,
            root: location,
            validationToken: ScanCacheValidation.applicationInventoryToken(
                at: location
            )
        )
    }

    public func save(
        applicationIdentity: ApplicationIdentity,
        for application: ApplicationRecord
    ) throws {
        try saveScanResult(
            applicationIdentity,
            key: "application-identity:"
                + application.url.standardizedFileURL.path,
            root: application.url,
            validationToken: ScanCacheValidation.token(for: application)
        )
    }

    public func cachedAIApplicationScan(
        key: String,
        root: URL
    ) throws -> AIApplicationScanResult? {
        try cachedScanResult(
            key: "ai-application:" + key,
            validationToken: ScanCacheValidation.token(for: root)
        )
    }

    public func save(
        aiApplicationScan: AIApplicationScanResult,
        key: String,
        root: URL
    ) throws {
        try saveScanResult(
            aiApplicationScan,
            key: "ai-application:" + key,
            root: root,
            validationToken: ScanCacheValidation.token(for: root)
        )
    }

    private func cachedScanResult<Value: Decodable>(
        key: String,
        validationToken: String
    ) throws -> Value? {
        do {
            return try connection.statement(
                """
                SELECT payload
                FROM scan_caches
                WHERE cache_key = ?
                  AND validation_token = ?
                  AND dirty = 0
                LIMIT 1;
                """
            ) { statement in
                try connection.bind(key, to: 1, in: statement)
                try connection.bind(validationToken, to: 2, in: statement)
                guard try connection.step(statement) == SQLITE_ROW else {
                    return nil
                }
                return try decoder.decode(
                    Value.self,
                    from: connection.blob(at: 0, in: statement)
                )
            }
        } catch is DecodingError {
            try connection.statement(
                "DELETE FROM scan_caches WHERE cache_key = ?;"
            ) { statement in
                try connection.bind(key, to: 1, in: statement)
                try connection.stepDone(statement)
            }
            return nil
        }
    }

    private func saveScanResult<Value: Encodable>(
        _ value: Value,
        key: String,
        root: URL,
        validationToken: String
    ) throws {
        let payload = try encoder.encode(value)
        try connection.statement(
            """
            INSERT INTO scan_caches(
                cache_key, root_path, validation_token, payload, dirty,
                updated_at
            ) VALUES (?, ?, ?, ?, 0, ?)
            ON CONFLICT(cache_key) DO UPDATE SET
                root_path = excluded.root_path,
                validation_token = excluded.validation_token,
                payload = excluded.payload,
                dirty = 0,
                updated_at = excluded.updated_at;
            """
        ) { statement in
            try connection.bind(key, to: 1, in: statement)
            try connection.bind(root.standardizedFileURL.path, to: 2, in: statement)
            try connection.bind(validationToken, to: 3, in: statement)
            try connection.bind(payload, to: 4, in: statement)
            try connection.bind(Date().timeIntervalSince1970, to: 5, in: statement)
            try connection.stepDone(statement)
        }
    }

    private func markScanCachesDirty(paths: [String]) throws {
        try connection.statement(
            """
            UPDATE scan_caches
            SET dirty = 1
            WHERE root_path = ?
               OR ? LIKE root_path || '/%'
               OR root_path LIKE ? || '/%';
            """
        ) { statement in
            for path in paths {
                for index: Int32 in 1...3 {
                    try connection.bind(path, to: index, in: statement)
                }
                try connection.stepDone(statement)
                try connection.reset(statement)
            }
        }
    }

    private func synchronize(
        graph: StorageIntelligenceGraph,
        snapshotID: String
    ) throws {
        try connection.statement(
            """
            INSERT INTO storage_owners(
                id, type, identifier, display_name, last_seen_snapshot
            ) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                type = excluded.type,
                identifier = excluded.identifier,
                display_name = excluded.display_name,
                last_seen_snapshot = excluded.last_seen_snapshot;
            """
        ) { statement in
            for owner in graph.owners {
                try connection.bind(owner.id, to: 1, in: statement)
                try connection.bind(owner.type.rawValue, to: 2, in: statement)
                try connection.bind(owner.identifier, to: 3, in: statement)
                try connection.bind(owner.displayName, to: 4, in: statement)
                try connection.bind(snapshotID, to: 5, in: statement)
                try connection.stepDone(statement)
                try connection.reset(statement)
            }
        }

        try connection.statement(
            """
            INSERT INTO storage_resources(
                id, path, kind, logical_size, allocated_size, modified_at,
                resource_identifier, category, risk, state, indexed_at,
                last_seen_snapshot
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                path = excluded.path,
                kind = excluded.kind,
                logical_size = excluded.logical_size,
                allocated_size = excluded.allocated_size,
                modified_at = excluded.modified_at,
                resource_identifier = excluded.resource_identifier,
                category = excluded.category,
                risk = excluded.risk,
                state = excluded.state,
                indexed_at = excluded.indexed_at,
                last_seen_snapshot = excluded.last_seen_snapshot;
            """
        ) { statement in
            for resource in graph.resources {
                try connection.bind(resource.id, to: 1, in: statement)
                try connection.bind(resource.url.path, to: 2, in: statement)
                try connection.bind(resource.kind.rawValue, to: 3, in: statement)
                try connection.bind(resource.logicalSize, to: 4, in: statement)
                try connection.bind(resource.allocatedSize, to: 5, in: statement)
                try connection.bind(
                    resource.modificationDate?.timeIntervalSince1970 ?? 0,
                    to: 6,
                    in: statement
                )
                try connection.bind(
                    resource.resourceIdentifier ?? "",
                    to: 7,
                    in: statement
                )
                try connection.bind(resource.category.rawValue, to: 8, in: statement)
                try connection.bind(resource.risk.rawValue, to: 9, in: statement)
                try connection.bind(resource.state.rawValue, to: 10, in: statement)
                try connection.bind(
                    resource.indexedAt.timeIntervalSince1970,
                    to: 11,
                    in: statement
                )
                try connection.bind(snapshotID, to: 12, in: statement)
                try connection.stepDone(statement)
                try connection.reset(statement)
            }
        }

        try connection.statement(
            """
            INSERT INTO storage_ownership(
                resource_id, owner_id, role, confidence, reason,
                last_seen_snapshot
            ) VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(resource_id, owner_id, role) DO UPDATE SET
                confidence = excluded.confidence,
                reason = excluded.reason,
                last_seen_snapshot = excluded.last_seen_snapshot;
            """
        ) { statement in
            for ownership in graph.ownerships {
                try connection.bind(ownership.resourceID, to: 1, in: statement)
                try connection.bind(ownership.ownerID, to: 2, in: statement)
                try connection.bind(ownership.role.rawValue, to: 3, in: statement)
                try connection.bind(Int64(ownership.confidence), to: 4, in: statement)
                try connection.bind(ownership.reason, to: 5, in: statement)
                try connection.bind(snapshotID, to: 6, in: statement)
                try connection.stepDone(statement)
                try connection.reset(statement)
            }
        }

        try connection.statement(
            """
            INSERT INTO directory_stats(
                resource_id, total_logical_size, total_allocated_size,
                file_count, directory_count, indexed_at, dirty,
                last_seen_snapshot
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(resource_id) DO UPDATE SET
                total_logical_size = excluded.total_logical_size,
                total_allocated_size = excluded.total_allocated_size,
                file_count = excluded.file_count,
                directory_count = excluded.directory_count,
                indexed_at = excluded.indexed_at,
                dirty = excluded.dirty,
                last_seen_snapshot = excluded.last_seen_snapshot;
            """
        ) { statement in
            for stat in graph.directoryStats {
                try connection.bind(stat.resourceID, to: 1, in: statement)
                try connection.bind(stat.totalLogicalSize, to: 2, in: statement)
                try connection.bind(stat.totalAllocatedSize, to: 3, in: statement)
                try connection.bind(Int64(stat.fileCount ?? -1), to: 4, in: statement)
                try connection.bind(
                    Int64(stat.directoryCount ?? -1),
                    to: 5,
                    in: statement
                )
                try connection.bind(
                    stat.indexedAt.timeIntervalSince1970,
                    to: 6,
                    in: statement
                )
                try connection.bind(stat.isDirty ? Int64(1) : 0, to: 7, in: statement)
                try connection.bind(snapshotID, to: 8, in: statement)
                try connection.stepDone(statement)
                try connection.reset(statement)
            }
        }

        try deleteRows(
            table: "storage_ownership",
            snapshotID: snapshotID
        )
        try deleteRows(
            table: "directory_stats",
            snapshotID: snapshotID
        )
        try deleteRows(
            table: "storage_resources",
            snapshotID: snapshotID
        )
        try deleteRows(
            table: "storage_owners",
            snapshotID: snapshotID
        )
        try connection.statement(
            """
            INSERT OR REPLACE INTO metadata(key, value)
            VALUES ('latest_storage_snapshot', ?);
            """
        ) { statement in
            try connection.bind(snapshotID, to: 1, in: statement)
            try connection.stepDone(statement)
        }
    }

    private func deleteRows(table: String, snapshotID: String) throws {
        try connection.statement(
            "DELETE FROM \(table) WHERE last_seen_snapshot <> ?;"
        ) { statement in
            try connection.bind(snapshotID, to: 1, in: statement)
            try connection.stepDone(statement)
        }
    }

    private static func text(
        at column: Int32,
        in statement: OpaquePointer
    ) -> String {
        sqlite3_column_text(statement, column).map(String.init(cString:)) ?? ""
    }

    private func metadataValue(for key: String) throws -> String? {
        try connection.statement(
            "SELECT value FROM metadata WHERE key = ? LIMIT 1;"
        ) { statement in
            try connection.bind(key, to: 1, in: statement)
            guard try connection.step(statement) == SQLITE_ROW else {
                return nil
            }
            return Self.text(at: 0, in: statement)
        }
    }

    private static func installSchema(on connection: SQLiteConnection) throws {
        for statement in IndexSchema.statements {
            try connection.execute(statement)
        }
        try connection.statement("PRAGMA quick_check;") { statement in
            guard try connection.step(statement) == SQLITE_ROW else {
                throw SQLiteStoreError(message: "SQLite integrity check returned no result")
            }
            guard let text = sqlite3_column_text(statement, 0),
                  String(cString: text) == "ok" else {
                throw SQLiteStoreError(
                    message: "SQLite integrity check failed",
                    confirmedCorruption: true
                )
            }
        }
    }

    private static func fileSize(at url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func removeStoreFiles(at url: URL) throws {
        for path in [url.path, url.path + "-wal", url.path + "-shm"] {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            try FileManager.default.removeItem(atPath: path)
        }
    }

    private static func quarantineCorruptStore(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let suffix = String(Int(Date().timeIntervalSince1970 * 1_000)) + "-" + UUID().uuidString
        let corruptURL = url.deletingLastPathComponent()
            .appending(path: url.lastPathComponent + ".corrupt-" + suffix)
        var movedSidecars: [(source: URL, destination: URL)] = []

        do {
            for sidecarSuffix in ["-wal", "-shm"] {
                let source = URL(fileURLWithPath: url.path + sidecarSuffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let destination = URL(fileURLWithPath: corruptURL.path + sidecarSuffix)
                try FileManager.default.moveItem(at: source, to: destination)
                movedSidecars.append((source, destination))
            }
            try FileManager.default.moveItem(at: url, to: corruptURL)
        } catch {
            var rollbackFailure: Error?
            for move in movedSidecars.reversed() {
                do {
                    try FileManager.default.moveItem(at: move.destination, to: move.source)
                } catch {
                    rollbackFailure = rollbackFailure ?? error
                }
            }
            if let rollbackFailure {
                throw SQLiteStoreError(
                    message: "SQLite quarantine failed: \(error.localizedDescription). "
                        + "Restoring sidecars also failed: \(rollbackFailure.localizedDescription)"
                )
            }
            throw error
        }
    }
}
