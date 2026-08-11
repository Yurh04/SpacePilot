import Foundation

/// The read-only overview facts for one Agent's detail pane.
public struct AIAgentOverviewDetail: Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let locality: AIAgentLocality
    public let formFactors: Set<AIAgentFormFactor>
    public let icon: AgentIconDescriptor
    public let detectedVersion: String?
    public let applicationURL: URL?
    public let executableURL: URL?
    public let aliasExecutableURLs: [URL]
    public let coverageFailures: Set<AIToolCoverageFailure>

    public init(
        id: String,
        displayName: String,
        locality: AIAgentLocality,
        formFactors: Set<AIAgentFormFactor>,
        icon: AgentIconDescriptor,
        detectedVersion: String?,
        applicationURL: URL?,
        executableURL: URL?,
        aliasExecutableURLs: [URL],
        coverageFailures: Set<AIToolCoverageFailure>
    ) {
        self.id = id
        self.displayName = displayName
        self.locality = locality
        self.formFactors = formFactors
        self.icon = icon
        self.detectedVersion = detectedVersion
        self.applicationURL = applicationURL
        self.executableURL = executableURL
        self.aliasExecutableURLs = aliasExecutableURLs
        self.coverageFailures = coverageFailures
    }
}

/// A fixed storage location for an Agent, with an already-computed allocated
/// size. Sizes are NOT computed here (no recursion on MainActor); callers pass
/// in sizes gathered from an existing snapshot, defaulting to 0 when unknown.
public struct AIAgentStorageItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case data
        case config
    }

    public var id: String { url.standardizedFileURL.path }
    public let kind: Kind
    public let url: URL
    public let allocatedSize: Int64

    public init(kind: Kind, url: URL, allocatedSize: Int64 = 0) {
        self.kind = kind
        self.url = url
        self.allocatedSize = allocatedSize
    }
}

/// Whether a detail module applies to an Agent, and if so its state. Remote
/// Agents that do not manage local storage/skills/plugins report
/// `.notApplicable` (honest "not available"), while local Agents keep the
/// module even when it has zero items (`.empty`).
public enum AIAgentModuleAvailability: Hashable, Sendable {
    case available
    case empty
    case notApplicable
}

/// A pure, read-only projection describing one Agent's detail modules
/// (overview / storage / skills / plugins), ready for the 6B UI to render. It
/// performs only filtering, ordering and counting — no file system access.
public struct AIAgentDetailProjection: Sendable, Equatable {
    public let overview: AIAgentOverviewDetail
    public let storageItems: [AIAgentStorageItem]
    public let storageAvailability: AIAgentModuleAvailability
    public let skills: [SkillRecord]
    public let skillsAvailability: AIAgentModuleAvailability
    public let plugins: [PluginRecord]
    public let pluginsAvailability: AIAgentModuleAvailability

    public var totalStorageSize: Int64 {
        storageItems.reduce(0) { $0 + $1.allocatedSize }
    }

    public init(
        agent: AIAgentEntry,
        skills: [SkillRecord],
        plugins: [PluginRecord],
        storageSizesByPath: [String: Int64] = [:]
    ) {
        self.overview = AIAgentOverviewDetail(
            id: agent.id,
            displayName: agent.displayName,
            locality: agent.locality,
            formFactors: agent.formFactors,
            icon: agent.icon,
            detectedVersion: agent.detectedVersion,
            applicationURL: agent.applicationURL,
            executableURL: agent.executableURL,
            aliasExecutableURLs: agent.aliasExecutableURLs,
            coverageFailures: agent.coverageFailures
        )

        let isRemote = agent.locality == .remote

        // Storage: fixed data + config roots, de-duplicated by canonical path,
        // ordered data-first then by path. Remote Agents report notApplicable.
        var seenStorage = Set<String>()
        var items: [AIAgentStorageItem] = []
        for url in agent.dataRoots {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seenStorage.insert(key).inserted else { continue }
            items.append(AIAgentStorageItem(kind: .data, url: url, allocatedSize: storageSizesByPath[key] ?? 0))
        }
        for url in agent.configDirectories {
            let key = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard seenStorage.insert(key).inserted else { continue }
            items.append(AIAgentStorageItem(kind: .config, url: url, allocatedSize: storageSizesByPath[key] ?? 0))
        }
        self.storageItems = items.sorted(by: Self.storageOrder)
        self.storageAvailability = isRemote
            ? .notApplicable
            : (items.isEmpty ? .empty : .available)

        // Skills / plugins owned by this Agent's definition. Shared assets are
        // never mixed into a per-Agent module (they belong to Global).
        let ownedSkills = skills
            .filter { Self.isOwned(by: agent.id, owner: $0.owner) }
            .sorted(by: Self.skillOrder)
        let ownedPlugins = plugins
            .filter { Self.isOwned(by: agent.id, owner: $0.owner) }
            .sorted(by: Self.pluginOrder)
        self.skills = ownedSkills
        self.plugins = ownedPlugins
        self.skillsAvailability = isRemote
            ? .notApplicable
            : (ownedSkills.isEmpty ? .empty : .available)
        self.pluginsAvailability = isRemote
            ? .notApplicable
            : (ownedPlugins.isEmpty ? .empty : .available)
    }

    private static func isOwned(by definitionID: String, owner: AIAssetOwner) -> Bool {
        if case .tool(let id) = owner { return id == definitionID }
        return false
    }

    /// Buckets already-scanned items under an Agent's fixed data/config roots,
    /// returning allocated sizes keyed by each root's canonical path. This is a
    /// pure aggregation over items already in memory — it performs no file system
    /// access. An item is attributed to the deepest (longest canonical path) root
    /// that contains it, so nested roots never double count. Roots with no items
    /// underneath are absent from the result (callers treat missing as 0).
    public static func storageSizes(
        items: [ScannedItem],
        forAgent agent: AIAgentEntry
    ) -> [String: Int64] {
        let roots = (agent.dataRoots + agent.configDirectories)
            .map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        guard !roots.isEmpty else { return [:] }
        // Deepest-first so the first containing root wins for nested layouts.
        let orderedRoots = Array(Set(roots)).sorted { $0.count > $1.count }
        var sizes: [String: Int64] = [:]
        for item in items {
            let itemPath = item.url.standardizedFileURL.resolvingSymlinksInPath().path
            for root in orderedRoots where Self.path(itemPath, isUnder: root) {
                sizes[root, default: 0] += item.allocatedSize
                break
            }
        }
        return sizes
    }

    private static func path(_ path: String, isUnder root: String) -> Bool {
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    private static func storageOrder(_ lhs: AIAgentStorageItem, _ rhs: AIAgentStorageItem) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .data }
        return lhs.url.standardizedFileURL.path < rhs.url.standardizedFileURL.path
    }

    private static func skillOrder(_ lhs: SkillRecord, _ rhs: SkillRecord) -> Bool {
        let name = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if name != .orderedSame { return name == .orderedAscending }
        if lhs.url.path != rhs.url.path { return lhs.url.path < rhs.url.path }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func pluginOrder(_ lhs: PluginRecord, _ rhs: PluginRecord) -> Bool {
        let name = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if name != .orderedSame { return name == .orderedAscending }
        if lhs.url.path != rhs.url.path { return lhs.url.path < rhs.url.path }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
