public enum IndexSchema {
    public static let statements = [
        "PRAGMA journal_mode=WAL;",
        "PRAGMA foreign_keys=ON;",
        "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS scan_sessions (id TEXT PRIMARY KEY, status TEXT NOT NULL, started_at REAL NOT NULL);",
        "CREATE TABLE IF NOT EXISTS snapshots (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, allocated_size INTEGER NOT NULL, status TEXT NOT NULL, payload BLOB NOT NULL);",
        "CREATE TABLE IF NOT EXISTS cleanup_history (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, payload BLOB NOT NULL);"
    ]
}
