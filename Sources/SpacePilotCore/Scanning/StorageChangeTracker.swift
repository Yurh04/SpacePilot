import Foundation

public actor StorageChangeTracker {
    private let root: URL
    private let store: SQLiteIndexStore
    private let fileManager: FileManager
    private let volumeID: String

    public init(
        root: URL,
        store: SQLiteIndexStore,
        fileManager: FileManager = .default
    ) {
        self.root = root.standardizedFileURL
        self.store = store
        self.fileManager = fileManager
        volumeID = FileSystemChangeMonitor.volumeID(for: root)
    }

    public func track(_ batch: FileSystemChangeBatch, observedAt: Date = .now) async throws -> StorageChangeHistory {
        let observation = diskObservation(at: observedAt)
        if batch.requiresFullInvalidation {
            try await store.recordStorageChangeUpdate(
                entries: [],
                states: [],
                removedPaths: [],
                observation: observation,
                gap: .init(
                    startedAt: observedAt,
                    reason: "FSEvents reported dropped or incomplete history"
                ),
                cursor: cursor(for: batch, observedAt: observedAt)
            )
            return try await store.storageChangeHistory()
        }

        let previous = try await store.storageChangeStates()
        var comparablePaths: [URL] = []
        var current: [String: StorageChangeFileState] = [:]
        for url in batch.changedPaths {
            let standardized = url.standardizedFileURL
            guard isInsideRoot(standardized) else { continue }
            if let state = liveState(
                at: standardized,
                observedAt: observedAt,
                eventID: batch.lastEventID,
                previous: previous
            ) {
                if state.isDirectory {
                    // File-events beneath the directory carry the useful byte
                    // deltas. Avoid replacing a recursive scan baseline with
                    // the directory inode's own tiny allocated size.
                    continue
                }
                comparablePaths.append(standardized)
                current[standardized.path] = state.value
            } else {
                comparablePaths.append(standardized)
            }
        }

        let detected = StorageChangeDetector.detect(
            paths: comparablePaths,
            previous: previous,
            current: current,
            observedAt: observedAt
        )
        try await store.recordStorageChangeUpdate(
            entries: detected.entries,
            states: detected.updatedStates,
            removedPaths: detected.removedPaths,
            observation: observation,
            cursor: cursor(for: batch, observedAt: observedAt)
        )
        return try await store.storageChangeHistory()
    }

    private func liveState(
        at url: URL,
        observedAt: Date,
        eventID: Int64,
        previous: [String: StorageChangeFileState]
    ) -> (value: StorageChangeFileState, isDirectory: Bool)? {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileResourceIdentifierKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        let prior = previous[url.path]
        let category = prior?.category ?? Self.category(for: url, root: root)
        return (
            StorageChangeFileState(
                url: url,
                allocatedSize: Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0),
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                category: category,
                ownerName: prior?.ownerName ?? Self.ownerName(for: url),
                risk: prior?.risk ?? Self.risk(for: url, category: category, root: root),
                observedAt: observedAt,
                lastEventID: eventID
            ),
            values.isDirectory == true
        )
    }

    private func diskObservation(at date: Date) -> DiskSpaceObservation? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? root.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? Int64(values.volumeAvailableCapacity ?? 0)
        return DiskSpaceObservation(
            observedAt: date,
            totalCapacity: Int64(total),
            availableCapacity: available
        )
    }

    private func cursor(
        for batch: FileSystemChangeBatch,
        observedAt: Date
    ) -> FileSystemEventCursor? {
        guard batch.lastEventID > 0 else { return nil }
        return FileSystemEventCursor(
            volumeID: volumeID,
            lastEventID: batch.lastEventID,
            lastReconciledAt: observedAt
        )
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        let path = url.path
        return path == root.path || path.hasPrefix(root.path + "/")
    }

    private static func category(for url: URL, root: URL) -> ItemCategory {
        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
        if relative.hasPrefix("Library/Caches/") || relative.hasPrefix(".cache/") {
            return .cache
        }
        if relative.hasPrefix("Library/Logs/") {
            return .log
        }
        if relative.hasPrefix("Library/Developer/") {
            return .developer
        }
        if relative.hasPrefix(".codex/") || relative.hasPrefix(".claude/")
            || relative.hasPrefix(".ollama/") {
            return .aiData
        }
        if relative.hasPrefix("Desktop/") || relative.hasPrefix("Documents/")
            || relative.hasPrefix("Downloads/") || relative.hasPrefix("Movies/")
            || relative.hasPrefix("Music/") || relative.hasPrefix("Pictures/") {
            return .personal
        }
        if relative.hasPrefix("Library/") {
            return .application
        }
        return .unclassified
    }

    private static func risk(
        for url: URL,
        category: ItemCategory,
        root: URL
    ) -> RiskLevel? {
        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
        guard category == .cache || category == .log else { return nil }
        guard relative.hasPrefix("Library/Caches/")
            || relative.hasPrefix("Library/Logs/")
            || relative.hasPrefix(".cache/") else { return nil }
        return .safe
    }

    private static func ownerName(for url: URL) -> String? {
        let components = url.pathComponents
        guard let libraryIndex = components.firstIndex(of: "Library"),
              components.indices.contains(libraryIndex + 2) else { return nil }
        let containerRoot = components[libraryIndex + 1]
        guard containerRoot == "Containers" || containerRoot == "Caches"
            || containerRoot == "Application Support" else { return nil }
        return components[libraryIndex + 2]
    }
}

public enum StorageChangeDetector {
    public struct Result: Sendable {
        public let entries: [StorageChangeEntry]
        public let updatedStates: [StorageChangeFileState]
        public let removedPaths: [String]
    }

    public static func detect(
        paths: [URL],
        previous: [String: StorageChangeFileState],
        current: [String: StorageChangeFileState],
        observedAt: Date
    ) -> Result {
        var candidates: [StorageChangeEntry] = []
        var updatedStates: [StorageChangeFileState] = []
        var removedPaths: [String] = []

        for url in paths {
            let path = url.standardizedFileURL.path
            let before = previous[path]
            let after = current[path]
            if let after {
                updatedStates.append(after)
                if let before {
                    if before.resourceIdentifier != nil,
                       after.resourceIdentifier != nil,
                       before.resourceIdentifier != after.resourceIdentifier {
                        candidates.append(entry(
                            state: before,
                            kind: .deleted,
                            before: before.allocatedSize,
                            after: 0,
                            observedAt: observedAt
                        ))
                        candidates.append(entry(
                            state: after,
                            kind: .added,
                            before: 0,
                            after: after.allocatedSize,
                            observedAt: observedAt
                        ))
                    } else if after.allocatedSize > before.allocatedSize {
                        candidates.append(entry(
                            state: after,
                            kind: .grown,
                            before: before.allocatedSize,
                            after: after.allocatedSize,
                            observedAt: observedAt
                        ))
                    }
                } else if after.allocatedSize > 0 {
                    candidates.append(entry(
                        state: after,
                        kind: .added,
                        before: 0,
                        after: after.allocatedSize,
                        observedAt: observedAt,
                        confidence: .estimated
                    ))
                }
            } else if let before {
                removedPaths.append(path)
                candidates.append(entry(
                    state: before,
                    kind: .deleted,
                    before: before.allocatedSize,
                    after: 0,
                    observedAt: observedAt
                ))
            }
        }

        let threshold = StorageChangeEntry.individualDisplayThreshold
        let individual = candidates.filter { $0.magnitudeBytes >= threshold }
        let small = candidates.filter { $0.magnitudeBytes < threshold }
        let grouped = Dictionary(grouping: small) { entry in
            GroupKey(
                path: entry.url.deletingLastPathComponent().path,
                kind: entry.kind,
                ownerName: entry.ownerName,
                category: entry.category,
                risk: entry.risk
            )
        }
        let aggregates = grouped.compactMap { key, values -> StorageChangeEntry? in
            let magnitude = values.reduce(Int64(0)) { $0 + $1.magnitudeBytes }
            guard magnitude >= threshold else { return nil }
            let before = values.reduce(Int64(0)) { $0 + $1.beforeBytes }
            let after = values.reduce(Int64(0)) { $0 + $1.afterBytes }
            return StorageChangeEntry(
                url: URL(fileURLWithPath: key.path, isDirectory: true),
                kind: key.kind,
                beforeBytes: before,
                afterBytes: after,
                startedAt: values.map(\.startedAt).min() ?? observedAt,
                observedAt: observedAt,
                category: key.category,
                ownerName: key.ownerName,
                risk: key.risk,
                isAggregated: true,
                confidence: values.contains { $0.confidence == .estimated } ? .estimated : .high
            )
        }
        return Result(
            entries: individual + aggregates,
            updatedStates: updatedStates,
            removedPaths: removedPaths
        )
    }

    private static func entry(
        state: StorageChangeFileState,
        kind: StorageChangeKind,
        before: Int64,
        after: Int64,
        observedAt: Date,
        confidence: StorageChangeConfidence = .high
    ) -> StorageChangeEntry {
        StorageChangeEntry(
            url: state.url,
            kind: kind,
            beforeBytes: before,
            afterBytes: after,
            startedAt: state.observedAt,
            observedAt: observedAt,
            category: state.category,
            ownerName: state.ownerName,
            risk: state.risk,
            confidence: confidence
        )
    }

    private struct GroupKey: Hashable {
        let path: String
        let kind: StorageChangeKind
        let ownerName: String?
        let category: ItemCategory?
        let risk: RiskLevel?
    }
}
