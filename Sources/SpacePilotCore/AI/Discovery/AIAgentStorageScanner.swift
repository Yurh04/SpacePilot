import Foundation

/// A complete metadata pass over an Agent's known roots, separate from the
/// disk overview's sampled/aggregated items. Never feeds cleanup candidates.
public struct AIAgentStorageSnapshot: Sendable, Equatable {
    public let items: [AIAgentStorageItem]
    public let sizesByPath: [String: Int64]
    public let coverageFailures: Set<AIToolCoverageFailure>

    public init(
        items: [AIAgentStorageItem],
        sizesByPath: [String: Int64] = [:],
        coverageFailures: Set<AIToolCoverageFailure> = []
    ) {
        self.items = items
        self.sizesByPath = sizesByPath
        self.coverageFailures = coverageFailures
    }
}

/// Reads only directory entries and file metadata. Nested symlinks are not
/// followed, packages are included, and overlapping roots are scanned once.
public struct AIAgentStorageScanner<Access: FileSystemAccess>: Sendable {
    private let access: Access

    public init(access: Access) {
        self.access = access
    }

    public func scan(agents: [AIAgentEntry]) throws -> [String: AIAgentStorageSnapshot] {
        var result: [String: AIAgentStorageSnapshot] = [:]
        for agent in agents where agent.locality == .local {
            try Task.checkCancellation()
            result[agent.id] = try scan(agent: agent)
        }
        return result
    }

    private func scan(agent: AIAgentEntry) throws -> AIAgentStorageSnapshot {
        let data = agent.dataRoots + agent.skillRoots + agent.pluginRoots
        let all = data + agent.configDirectories
        var seenRoots = Set<String>()
        let roots = all.map(\.canonicalizedForDiscovery).sorted { $0.path < $1.path }
            .filter { seenRoots.insert($0.path).inserted }
        let outerRoots = roots.filter { candidate in
            !roots.contains { $0 != candidate && candidate.path.hasPrefix($0.path + "/") }
        }
        let dataPaths = Set(data.map(\.canonicalizedDiscoveryPath))
        var items: [AIAgentStorageItem] = []
        var sizesByPath: [String: Int64] = [:]
        var failures = agent.coverageFailures.intersection([.permissionDenied])
        var seenFiles = Set<String>()

        for root in outerRoots {
            try Task.checkCancellation()
            let kind: AIAgentStorageItem.Kind = dataPaths.contains(root.path) ? .data : .config
            let children: [URL]
            do {
                children = try access.contentsOfDirectory(at: root)
            } catch {
                failures.insert(.permissionDenied)
                items.append(AIAgentStorageItem(kind: kind, url: root, isSizeKnown: false))
                continue
            }
            if children.isEmpty {
                items.append(AIAgentStorageItem(kind: kind, url: root))
            }
            for child in children.sorted(by: { $0.path < $1.path }) {
                var size: Int64 = 0
                var complete = true
                var pending = [child]
                var processed = 0
                while let url = pending.popLast() {
                    processed += 1
                    if processed.isMultiple(of: 128) { try Task.checkCancellation() }
                    do {
                        try autoreleasepool {
                            let metadata = try access.metadata(at: url)
                            if metadata.isDirectory && !metadata.isSymbolicLink {
                                pending.append(contentsOf: try access.contentsOfDirectory(at: url))
                            } else if metadata.isRegularFile || metadata.isSymbolicLink {
                                let identity = metadata.resourceIdentifier ?? url.standardizedFileURL.path
                                guard seenFiles.insert(identity).inserted else { return }
                                size += metadata.allocatedSize
                            }
                        }
                    } catch {
                        complete = false
                        failures.insert(.permissionDenied)
                    }
                }
                items.append(AIAgentStorageItem(
                    kind: kind, url: child, allocatedSize: size,
                    category: Self.category(for: child), isSizeKnown: complete
                ))
                sizesByPath[root.path, default: 0] += size
            }
        }
        try Task.checkCancellation()
        return AIAgentStorageSnapshot(
            items: items.sorted {
                if $0.allocatedSize != $1.allocatedSize { return $0.allocatedSize > $1.allocatedSize }
                return $0.url.path < $1.url.path
            },
            sizesByPath: sizesByPath,
            coverageFailures: failures
        )
    }

    /// Semantic filename rules, independent of Agent brand or database version.
    /// Unknown entries remain visible as AI data rather than being dropped.
    public static func category(for url: URL) -> ItemCategory {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()
        if ["plugins", "extensions", "marketplaces"].contains(name) { return .plugin }
        if ["skills", "builtin_skills"].contains(name) { return .skill }
        if ["sessions", "archived_sessions", "conversations", "projects", "history"].contains(name)
            || name.hasPrefix("history.") || name.hasPrefix("thread_history")
            || name.hasPrefix("session_index") || name.hasPrefix("transcription-history") {
            return .conversation
        }
        if ["logs", "log", "debug", "telemetry", "tea_logs"].contains(name)
            || name.hasPrefix("logs_") || name.hasSuffix(".log") || path.contains("/library/logs/") {
            return .log
        }
        if name.contains("cache") || ["tmp", ".tmp"].contains(name)
            || path.contains("/library/caches/") { return .cache }
        if ["models", "blobs", "weights"].contains(name) { return .model }
        return .aiData
    }
}
