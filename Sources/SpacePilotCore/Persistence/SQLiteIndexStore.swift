import Foundation
import SQLite3

public protocol SnapshotStoring: Sendable {
    func save(snapshot: ScanSnapshot) async throws
    func latestSnapshot() async throws -> ScanSnapshot?
    func save(transaction: CleanupTransaction) async throws
    func cleanupHistory() async throws -> [CleanupTransaction]
}

public actor SQLiteIndexStore: SnapshotStoring {
    private let connection: SQLiteConnection
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
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
        } catch {
            if FileManager.default.fileExists(atPath: url.path) {
                let suffix = String(Int(Date().timeIntervalSince1970 * 1_000))
                let corruptURL = url.deletingLastPathComponent()
                    .appending(path: url.lastPathComponent + ".corrupt-" + suffix)
                try FileManager.default.moveItem(at: url, to: corruptURL)
                for sidecarSuffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: url.path + sidecarSuffix)
                    if FileManager.default.fileExists(atPath: sidecar.path) {
                        try? FileManager.default.moveItem(
                            at: sidecar,
                            to: URL(fileURLWithPath: corruptURL.path + sidecarSuffix)
                        )
                    }
                }
            }
            let fresh = try SQLiteConnection(url: url)
            try Self.installSchema(on: fresh)
            connection = fresh
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
        let payload = try encoder.encode(snapshot)
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

    private static func installSchema(on connection: SQLiteConnection) throws {
        for statement in IndexSchema.statements {
            try connection.execute(statement)
        }
        try connection.statement("PRAGMA quick_check;") { statement in
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0),
                  String(cString: text) == "ok" else {
                throw SQLiteStoreError(message: "SQLite integrity check failed")
            }
        }
    }
}
