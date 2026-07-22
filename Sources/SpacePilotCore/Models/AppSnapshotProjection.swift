import Foundation

public struct AppSnapshotProjection: Sendable {
    public let snapshotID: UUID
    public let overview: OverviewProjection
    public let storage: StorageProjection
    public let applications: ApplicationListProjection
    public let developerAI: DeveloperAIProjection

    public init(snapshot: ScanSnapshot) {
        self.init(
            snapshotID: snapshot.id,
            overview: OverviewProjection(snapshot: snapshot),
            storage: StorageProjection(snapshot: snapshot),
            applications: ApplicationListProjection(snapshot: snapshot, searchText: ""),
            developerAI: DeveloperAIProjection(snapshot: snapshot)
        )
    }

    public static func build(snapshot: ScanSnapshot) throws -> Self {
        let checkCancellation: @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
        return try build(snapshot: snapshot, checkCancellation: checkCancellation)
    }

    static func build(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws -> Self {
        try checkCancellation()
        let overview = try OverviewProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let storage = try StorageProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let applications = try ApplicationListProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let developerAI = try DeveloperAIProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        return Self(
            snapshotID: snapshot.id,
            overview: overview,
            storage: storage,
            applications: applications,
            developerAI: developerAI
        )
    }

    private init(
        snapshotID: UUID,
        overview: OverviewProjection,
        storage: StorageProjection,
        applications: ApplicationListProjection,
        developerAI: DeveloperAIProjection
    ) {
        self.snapshotID = snapshotID
        self.overview = overview
        self.storage = storage
        self.applications = applications
        self.developerAI = developerAI
    }
}

public struct AIApplicationProjection: Identifiable, Sendable {
    public var id: UUID { application.id }
    public let application: AIApplicationRecord
    public let totalSize: Int64
    public let dataItems: [ScannedItem]
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]

    public init(
        application: AIApplicationRecord,
        totalSize: Int64,
        dataItems: [ScannedItem],
        plugins: [PluginRecord],
        skills: [SkillRecord]
    ) {
        self.application = application
        self.totalSize = totalSize
        self.dataItems = dataItems
        self.plugins = plugins
        self.skills = skills
    }
}

public struct AIApplicationQueryProjection: Sendable {
    public let applicationID: UUID
    public let query: String
    public let dataItems: [ScannedItem]
    public let skills: [SkillRecord]

    public static func build(
        application: AIApplicationProjection,
        query: String
    ) throws -> Self {
        try Task.checkCancellation()
        guard !query.isEmpty else {
            let result = Self(
                applicationID: application.id,
                query: query,
                dataItems: application.dataItems,
                skills: application.skills
            )
            try Task.checkCancellation()
            return result
        }

        var checkpoint = ProjectionCancellationCheckpoint {
            try Task.checkCancellation()
        }
        var dataItems: [ScannedItem] = []
        for item in application.dataItems {
            try checkpoint.checkPeriodically()
            if item.url.path.localizedCaseInsensitiveContains(query) {
                dataItems.append(item)
            }
        }
        var skills: [SkillRecord] = []
        for skill in application.skills {
            try checkpoint.checkPeriodically()
            if skill.name.localizedCaseInsensitiveContains(query) {
                skills.append(skill)
            }
        }
        let result = Self(
            applicationID: application.id,
            query: query,
            dataItems: dataItems,
            skills: skills
        )
        try Task.checkCancellation()
        return result
    }
}

public struct DeveloperAIProjection: Sendable {
    public let developerBytes: Int64
    public let applications: [AIApplicationProjection]
    public let pluginDiagnostics: [String]

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        try checkCancellation()
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var pluginsByID: [UUID: PluginRecord] = [:]
        for plugin in snapshot.plugins {
            try checkpoint.checkPeriodically()
            pluginsByID[plugin.id] = plugin
        }
        var skillsByID: [UUID: SkillRecord] = [:]
        for skill in snapshot.skills {
            try checkpoint.checkPeriodically()
            skillsByID[skill.id] = skill
        }

        var applicationIDByItemID: [UUID: UUID] = [:]
        for application in snapshot.aiApplications {
            try checkpoint.checkPeriodically()
            for itemID in application.itemIDs {
                try checkpoint.checkPeriodically()
                applicationIDByItemID[itemID] = application.id
            }
        }

        var developerItemBytes: Int64 = 0
        var dataItemsByApplicationID: [UUID: [ScannedItem]] = [:]
        for item in snapshot.items {
            try checkpoint.checkPeriodically()
            if item.category == .developer {
                developerItemBytes += item.allocatedSize
            }
            if let applicationID = applicationIDByItemID[item.id] {
                dataItemsByApplicationID[applicationID, default: []].append(item)
            }
        }

        developerBytes = developerItemBytes
        var applicationProjections: [AIApplicationProjection] = []
        applicationProjections.reserveCapacity(snapshot.aiApplications.count)
        for application in snapshot.aiApplications {
            try checkpoint.checkPeriodically()
            let dataItems = try ProjectionCancellationAwareOrdering.sorted(
                dataItemsByApplicationID[application.id, default: []],
                by: { $0.allocatedSize > $1.allocatedSize },
                checkCancellation: checkCancellation
            )

            var unorderedPlugins: [PluginRecord] = []
            unorderedPlugins.reserveCapacity(application.pluginIDs.count)
            for pluginID in application.pluginIDs {
                try checkpoint.checkPeriodically()
                if let plugin = pluginsByID[pluginID] {
                    unorderedPlugins.append(plugin)
                }
            }
            let plugins = try ProjectionCancellationAwareOrdering.sorted(
                unorderedPlugins,
                by: {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                checkCancellation: checkCancellation
            )

            var unorderedSkills: [SkillRecord] = []
            unorderedSkills.reserveCapacity(application.skillIDs.count)
            for skillID in application.skillIDs {
                try checkpoint.checkPeriodically()
                if let skill = skillsByID[skillID] {
                    unorderedSkills.append(skill)
                }
            }
            let skills = try ProjectionCancellationAwareOrdering.sorted(
                unorderedSkills,
                by: {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                checkCancellation: checkCancellation
            )

            var managedAssets: [AIManagedAssetCandidate] = []
            managedAssets.reserveCapacity(plugins.count + skills.count)
            for plugin in plugins {
                try checkpoint.checkPeriodically()
                managedAssets.append(AIManagedAssetCandidate(
                    kind: .plugin,
                    url: plugin.url,
                    allocatedSize: plugin.allocatedSize
                ))
            }
            for skill in skills {
                try checkpoint.checkPeriodically()
                if let parentPluginID = skill.parentPluginID,
                   application.pluginIDs.contains(parentPluginID) {
                    continue
                }
                managedAssets.append(AIManagedAssetCandidate(
                    kind: .standaloneSkill,
                    url: skill.url,
                    allocatedSize: skill.allocatedSize
                ))
            }
            let ownership = try AIManagedAssetOwnership(
                candidates: managedAssets,
                checkCancellation: checkCancellation
            )
            var dataItemBytes: Int64 = 0
            for item in dataItems {
                try checkpoint.checkPeriodically()
                if !ownership.contains(item.url) {
                    dataItemBytes += item.allocatedSize
                }
            }
            let totalSize = application.applicationAllocatedSize
                + dataItemBytes
                + ownership.pluginBytes
                + ownership.standaloneSkillBytes
            applicationProjections.append(AIApplicationProjection(
                application: application,
                totalSize: totalSize,
                dataItems: dataItems,
                plugins: plugins,
                skills: skills
            ))
            try checkCancellation()
        }
        applications = applicationProjections
        pluginDiagnostics = snapshot.pluginDiagnostics ?? []
        try checkCancellation()
    }
}

private enum AIManagedAssetKind: Int, Sendable {
    case plugin
    case standaloneSkill
}

private struct AIManagedAssetCandidate: Sendable {
    let kind: AIManagedAssetKind
    let url: URL
    let allocatedSize: Int64
}

/// Assigns each physical managed directory to one aggregate component and provides
/// component-safe containment checks for the file-level rows scanned beneath it.
private struct AIManagedAssetOwnership: Sendable {
    let pluginBytes: Int64
    let standaloneSkillBytes: Int64

    private let knownRoots: Set<String>

    init(
        candidates: [AIManagedAssetCandidate],
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        struct NormalizedCandidate {
            let candidate: AIManagedAssetCandidate
            let standardizedURL: URL
            let canonicalURL: URL
        }

        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var normalized: [NormalizedCandidate] = []
        normalized.reserveCapacity(candidates.count)
        for candidate in candidates {
            try checkpoint.checkPeriodically()
            let standardizedURL = candidate.url.standardizedFileURL
            let canonicalURL = FileManager.default.fileExists(atPath: standardizedURL.path)
                ? standardizedURL.resolvingSymlinksInPath()
                : standardizedURL
            normalized.append(NormalizedCandidate(
                candidate: candidate,
                standardizedURL: standardizedURL,
                canonicalURL: canonicalURL
            ))
        }
        normalized = try ProjectionCancellationAwareOrdering.sorted(
            normalized,
            by: { lhs, rhs in
                let lhsDepth = lhs.canonicalURL.pathComponents.count
                let rhsDepth = rhs.canonicalURL.pathComponents.count
                if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
                if lhs.canonicalURL.path != rhs.canonicalURL.path {
                    return lhs.canonicalURL.path < rhs.canonicalURL.path
                }
                return lhs.candidate.kind.rawValue < rhs.candidate.kind.rawValue
            },
            checkCancellation: checkCancellation
        )

        var acceptedCanonicalRoots: Set<String> = []
        var knownRoots: Set<String> = []
        var pluginBytes: Int64 = 0
        var standaloneSkillBytes: Int64 = 0
        for entry in normalized {
            try checkpoint.checkPeriodically()
            let isAlreadyOwned = Self.contains(
                entry.canonicalURL.path,
                in: acceptedCanonicalRoots
            )

            // Retain both known spellings even when another accepted ancestor owns
            // the bytes. This handles scanner rows using either a symlink path or
            // its resolved target without resolving every one of millions of rows.
            knownRoots.insert(entry.standardizedURL.path)
            knownRoots.insert(entry.canonicalURL.path)
            guard !isAlreadyOwned else { continue }

            acceptedCanonicalRoots.insert(entry.canonicalURL.path)
            switch entry.candidate.kind {
            case .plugin:
                pluginBytes += entry.candidate.allocatedSize
            case .standaloneSkill:
                standaloneSkillBytes += entry.candidate.allocatedSize
            }
        }

        self.pluginBytes = pluginBytes
        self.standaloneSkillBytes = standaloneSkillBytes
        self.knownRoots = knownRoots
    }

    func contains(_ url: URL) -> Bool {
        Self.contains(url.standardizedFileURL.path, in: knownRoots)
    }

    private static func contains(_ path: String, in roots: Set<String>) -> Bool {
        guard !roots.isEmpty else { return false }
        var current = path
        while true {
            if roots.contains(current) { return true }
            guard current != "/", let separator = current.lastIndex(of: "/") else {
                return false
            }
            current = separator == current.startIndex ? "/" : String(current[..<separator])
        }
    }
}
