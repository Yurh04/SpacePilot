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
    public let category: ItemCategory
    public let isSizeKnown: Bool

    public init(
        kind: Kind, url: URL, allocatedSize: Int64 = 0,
        category: ItemCategory = .aiData, isSizeKnown: Bool = true
    ) {
        self.kind = kind
        self.url = url
        self.allocatedSize = allocatedSize
        self.category = category
        self.isSizeKnown = isSizeKnown
    }
}

/// One row of an Agent's storage "space breakdown": how much of its indexed
/// footprint falls into a semantic category (conversations, logs, cache, model
/// data, plugins, skills, …). Categories come from `ScannedItem.category`, which
/// the adapters already tag, so this is a pure aggregation with no file access.
public struct AIAgentStorageCategory: Identifiable, Hashable, Sendable {
    public let category: ItemCategory
    public let allocatedSize: Int64

    public var id: String { category.rawValue }

    public init(category: ItemCategory, allocatedSize: Int64) {
        self.category = category
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
    /// Shared skills that are visible to this Agent but owned by no single tool.
    /// Kept separate from `skills` so the UI can offer an explicit
    /// "this Agent" / "Global" switch without ever conflating the two: deleting a
    /// shared skill affects every Agent, an owned one does not.
    public let globalSkills: [SkillRecord]
    public let globalSkillsAvailability: AIAgentModuleAvailability
    public let plugins: [PluginRecord]
    public let pluginsAvailability: AIAgentModuleAvailability
    /// Indexed footprint split by semantic category (conversations/logs/cache/…),
    /// largest first. Empty when no per-category sizes were supplied (for example
    /// a remote Agent, or a caller that did not pass a breakdown).
    public let storageBreakdown: [AIAgentStorageCategory]
    public let storageCoverageFailures: Set<AIToolCoverageFailure>
    public let pluginNamesByID: [UUID: String]

    public func sourcePluginName(for skill: SkillRecord) -> String? {
        if let id = skill.parentPluginID, let name = pluginNamesByID[id] { return name }
        if case .pluginProvided(let name) = skill.scope { return name }
        if case .plugin(let name) = skill.owner { return name }
        return nil
    }

    public var totalStorageSize: Int64 {
        storageItems.reduce(0) { $0 + $1.allocatedSize }
    }

    public init(
        agent: AIAgentEntry,
        skills: [SkillRecord],
        plugins: [PluginRecord],
        storageSizesByPath: [String: Int64] = [:],
        storageSizesByCategory: [ItemCategory: Int64] = [:],
        storageSnapshot: AIAgentStorageSnapshot? = nil
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
            let key = url.canonicalizedDiscoveryPath
            guard seenStorage.insert(key).inserted else { continue }
            items.append(AIAgentStorageItem(
                kind: .data, url: url, allocatedSize: storageSizesByPath[key] ?? 0,
                isSizeKnown: storageSizesByPath[key] != nil
            ))
        }
        for url in agent.configDirectories {
            let key = url.canonicalizedDiscoveryPath
            guard seenStorage.insert(key).inserted else { continue }
            items.append(AIAgentStorageItem(
                kind: .config, url: url, allocatedSize: storageSizesByPath[key] ?? 0,
                isSizeKnown: storageSizesByPath[key] != nil
            ))
        }
        let resolvedItems = storageSnapshot?.items ?? items.sorted(by: Self.storageOrder)
        self.storageItems = isRemote ? [] : resolvedItems
        self.storageCoverageFailures = storageSnapshot?.coverageFailures ?? []
        self.storageAvailability = isRemote
            ? .notApplicable
            : (resolvedItems.isEmpty ? .empty : .available)

        // Space breakdown by semantic category. Remote Agents manage no local
        // storage, so they report none. Zero-size categories are dropped and the
        // rest are ordered largest-first for a stable, meaningful bar chart.
        let categorySizes = storageSnapshot.map { snapshot in
            Dictionary(grouping: snapshot.items, by: \.category).mapValues {
                $0.reduce(Int64(0)) { $0 + $1.allocatedSize }
            }
        } ?? storageSizesByCategory
        self.storageBreakdown = isRemote
            ? []
            : categorySizes
                .filter { $0.value > 0 }
                .map { AIAgentStorageCategory(category: $0.key, allocatedSize: $0.value) }
                .sorted(by: Self.categoryOrder)

        // Skills / plugins owned by this Agent's definition. Shared assets are
        // reported separately in `globalSkills` (they are visible to this Agent
        // but owned by no single tool), so per-Agent counts stay honest. A
        // plugin-provided skill is attributed to whichever tool owns its parent
        // plugin, mirroring AIAssetGroupingProjection so the detail pane's skill
        // count matches the sidebar grouping.
        let pluginOwnerByID = Dictionary(
            plugins.map { ($0.id, $0.owner) },
            uniquingKeysWith: { first, _ in first }
        )
        self.pluginNamesByID = Dictionary(
            plugins.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }
        )
        let ownedSkills = skills
            .filter { Self.isOwned(by: agent.id, skill: $0, pluginOwnerByID: pluginOwnerByID) }
            .sorted(by: Self.skillOrder)
        let ownedPlugins = plugins
            .filter { Self.isOwned(by: agent.id, owner: $0.owner) }
            .sorted(by: Self.pluginOrder)
        let sharedSkills = isRemote
            ? []
            : skills
                .filter { $0.owner == .shared }
                .sorted(by: Self.skillOrder)
        self.skills = ownedSkills
        self.plugins = ownedPlugins
        self.globalSkills = sharedSkills
        self.skillsAvailability = isRemote
            ? .notApplicable
            : (ownedSkills.isEmpty ? .empty : .available)
        self.globalSkillsAvailability = isRemote
            ? .notApplicable
            : (sharedSkills.isEmpty ? .empty : .available)
        self.pluginsAvailability = isRemote
            ? .notApplicable
            : (ownedPlugins.isEmpty ? .empty : .available)
    }

    private static func isOwned(by definitionID: String, owner: AIAssetOwner) -> Bool {
        if case .tool(let id) = owner { return id == definitionID }
        return false
    }

    /// A skill is owned by an Agent when it is directly owned by that tool, or
    /// when it is provided by a plugin whose owner is that tool. Resolving the
    /// parent-plugin chain here keeps the detail pane consistent with
    /// `AIAssetGroupingProjection`, which folds plugin-provided skills into their
    /// parent plugin's tool owner.
    private static func isOwned(
        by definitionID: String,
        skill: SkillRecord,
        pluginOwnerByID: [UUID: AIAssetOwner]
    ) -> Bool {
        if case .plugin = skill.owner {
            guard let pluginID = skill.parentPluginID,
                  let pluginOwner = pluginOwnerByID[pluginID] else { return false }
            return isOwned(by: definitionID, owner: pluginOwner)
        }
        return isOwned(by: definitionID, owner: skill.owner)
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
        storageSizes(items: items, forAgents: [agent])[agent.id] ?? [:]
    }

    /// Buckets scanned items for many Agents in a single pass, keyed by Agent id.
    ///
    /// Canonicalising a path is a file-system syscall (measured ~3 µs), so the
    /// per-Agent overload multiplies that cost by the number of Agents. This
    /// overload canonicalises each item exactly once and reuses the result for
    /// every Agent, which is what keeps the detail pane cheap to re-render.
    public static func storageSizes(
        items: [ScannedItem],
        forAgents agents: [AIAgentEntry]
    ) -> [String: [String: Int64]] {
        // Canonical roots per Agent, deepest-first so the first containing root
        // wins for nested layouts.
        var rootsByAgent: [(agentID: String, roots: [String])] = []
        var allRoots: Set<String> = []
        for agent in agents {
            let roots = (agent.dataRoots + agent.configDirectories)
                .map { $0.canonicalizedDiscoveryPath }
            guard !roots.isEmpty else { continue }
            let ordered = Array(Set(roots)).sorted { $0.count > $1.count }
            rootsByAgent.append((agent.id, ordered))
            allRoots.formUnion(ordered)
        }
        guard !rootsByAgent.isEmpty else { return [:] }

        var result: [String: [String: Int64]] = [:]
        for item in items {
            // One canonicalisation per item, shared across all Agents.
            let itemPath = item.url.canonicalizedDiscoveryPath
            for (agentID, roots) in rootsByAgent {
                for root in roots where Self.path(itemPath, isUnder: root) {
                    result[agentID, default: [:]][root, default: 0] += item.allocatedSize
                    break
                }
            }
        }
        return result
    }

    private static func path(_ path: String, isUnder root: String) -> Bool {
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    /// Buckets scanned items for many Agents by semantic `ItemCategory`, keyed by
    /// Agent id. Same containment rule as `storageSizes(items:forAgents:)` (an
    /// item counts once, under the deepest containing root), but the inner tally
    /// is per category rather than per root. Pure aggregation, one canonicalise
    /// per item, no file access — safe to call from a cached MainActor path.
    public static func storageSizesByCategory(
        items: [ScannedItem],
        forAgents agents: [AIAgentEntry]
    ) -> [String: [ItemCategory: Int64]] {
        var rootsByAgent: [(agentID: String, roots: [String])] = []
        for agent in agents {
            let roots = (agent.dataRoots + agent.configDirectories)
                .map { $0.canonicalizedDiscoveryPath }
            guard !roots.isEmpty else { continue }
            let ordered = Array(Set(roots)).sorted { $0.count > $1.count }
            rootsByAgent.append((agent.id, ordered))
        }
        guard !rootsByAgent.isEmpty else { return [:] }

        var result: [String: [ItemCategory: Int64]] = [:]
        for item in items {
            let itemPath = item.url.canonicalizedDiscoveryPath
            for (agentID, roots) in rootsByAgent {
                for root in roots where Self.path(itemPath, isUnder: root) {
                    result[agentID, default: [:]][item.category, default: 0] += item.allocatedSize
                    break
                }
            }
        }
        return result
    }

    private static func categoryOrder(_ lhs: AIAgentStorageCategory, _ rhs: AIAgentStorageCategory) -> Bool {
        if lhs.allocatedSize != rhs.allocatedSize { return lhs.allocatedSize > rhs.allocatedSize }
        return lhs.category.rawValue < rhs.category.rawValue
    }

    private static func storageOrder(_ lhs: AIAgentStorageItem, _ rhs: AIAgentStorageItem) -> Bool {
        if lhs.kind != rhs.kind { return lhs.kind == .data }
        return lhs.url.canonicalizedDiscoveryPath < rhs.url.canonicalizedDiscoveryPath
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
