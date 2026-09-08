public enum IndexSchema {
    public static let currentVersion = 4

    public static let statements = [
        "PRAGMA journal_mode=WAL;",
        "PRAGMA foreign_keys=ON;",
        "PRAGMA user_version=4;",
        "CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        "CREATE TABLE IF NOT EXISTS scan_sessions (id TEXT PRIMARY KEY, status TEXT NOT NULL, started_at REAL NOT NULL);",
        "CREATE TABLE IF NOT EXISTS snapshots (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, allocated_size INTEGER NOT NULL, status TEXT NOT NULL, payload BLOB NOT NULL);",
        "CREATE TABLE IF NOT EXISTS cleanup_history (id TEXT PRIMARY KEY, completed_at REAL NOT NULL, payload BLOB NOT NULL);",
        """
        CREATE TABLE IF NOT EXISTS storage_owners (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            identifier TEXT NOT NULL,
            display_name TEXT NOT NULL,
            last_seen_snapshot TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS storage_resources (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL UNIQUE,
            kind TEXT NOT NULL,
            logical_size INTEGER NOT NULL,
            allocated_size INTEGER NOT NULL,
            modified_at REAL NOT NULL,
            resource_identifier TEXT NOT NULL,
            category TEXT NOT NULL,
            risk TEXT NOT NULL,
            state TEXT NOT NULL,
            indexed_at REAL NOT NULL,
            last_seen_snapshot TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS storage_ownership (
            resource_id TEXT NOT NULL REFERENCES storage_resources(id) ON DELETE CASCADE,
            owner_id TEXT NOT NULL REFERENCES storage_owners(id) ON DELETE CASCADE,
            role TEXT NOT NULL,
            confidence INTEGER NOT NULL,
            reason TEXT NOT NULL,
            last_seen_snapshot TEXT NOT NULL,
            PRIMARY KEY(resource_id, owner_id, role)
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS directory_stats (
            resource_id TEXT PRIMARY KEY REFERENCES storage_resources(id) ON DELETE CASCADE,
            total_logical_size INTEGER NOT NULL,
            total_allocated_size INTEGER NOT NULL,
            file_count INTEGER NOT NULL,
            directory_count INTEGER NOT NULL,
            indexed_at REAL NOT NULL,
            dirty INTEGER NOT NULL,
            last_seen_snapshot TEXT NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS fsevent_cursors (
            volume_id TEXT PRIMARY KEY,
            last_event_id INTEGER NOT NULL,
            last_reconciled_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS scan_caches (
            cache_key TEXT PRIMARY KEY,
            root_path TEXT NOT NULL,
            validation_token TEXT NOT NULL,
            payload BLOB NOT NULL,
            dirty INTEGER NOT NULL,
            updated_at REAL NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS storage_change_states (
            path TEXT PRIMARY KEY,
            updated_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS storage_change_events (
            id TEXT PRIMARY KEY,
            path TEXT NOT NULL,
            kind TEXT NOT NULL,
            magnitude INTEGER NOT NULL,
            observed_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS disk_space_observations (
            id TEXT PRIMARY KEY,
            observed_at REAL NOT NULL,
            payload BLOB NOT NULL
        );
        """,
        """
        CREATE TABLE IF NOT EXISTS storage_change_gaps (
            id TEXT PRIMARY KEY,
            started_at REAL NOT NULL,
            ended_at REAL,
            payload BLOB NOT NULL
        );
        """,
        "CREATE INDEX IF NOT EXISTS storage_resources_category_size ON storage_resources(category, allocated_size DESC);",
        "CREATE INDEX IF NOT EXISTS storage_resources_state ON storage_resources(state);",
        "CREATE INDEX IF NOT EXISTS storage_ownership_owner ON storage_ownership(owner_id, role);",
        "CREATE INDEX IF NOT EXISTS scan_caches_root ON scan_caches(root_path, dirty);",
        "CREATE INDEX IF NOT EXISTS storage_change_events_time ON storage_change_events(observed_at DESC);",
        "CREATE INDEX IF NOT EXISTS storage_change_events_kind_time ON storage_change_events(kind, observed_at DESC);",
        "CREATE INDEX IF NOT EXISTS disk_space_observations_time ON disk_space_observations(observed_at DESC);"
    ]
}
