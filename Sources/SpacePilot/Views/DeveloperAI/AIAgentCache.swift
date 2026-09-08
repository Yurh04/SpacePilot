import Foundation
import SpacePilotCore

/// Caches the pure-but-expensive projections behind the Developer & AI detail
/// pane so that re-rendering a pane does not redo work whose inputs have not
/// changed.
///
/// Why this exists: `AIAgentProjection` and the storage-size bucketing are pure
/// functions, which makes them safe to call from `body` — but not free.
/// `AIAgentDetailProjection.storageSizes` canonicalises every scanned path, and
/// canonicalising is a file-system syscall (measured ~3 µs each). With a few
/// thousand scanned items that is hundreds of milliseconds per `body`
/// evaluation, and SwiftUI evaluates `body` on every selection change,
/// keystroke and window resize.
///
/// Both caches are keyed by the identity of their inputs, so a stale value can
/// never be observed: a new scan produces a new snapshot id, and changed
/// discovery records fail the equality check.
///
/// MainActor-isolated, matching the views that read it; no locking needed.
@MainActor
final class AIAgentCache {
    static let shared = AIAgentCache()

    private var projectionRecords: [AIToolRecord] = []
    private var cachedProjection: AIAgentProjection?

    private var storageKey: StorageKey?
    private var cachedStorageSizes: [String: Int64] = [:]
    private var categoryKey: StorageKey?
    private var cachedCategorySizes: [String: [ItemCategory: Int64]] = [:]

    private struct StorageKey: Equatable {
        let snapshotID: UUID
        let itemCount: Int
        let agentIDs: [String]
    }

    private init() {}

    /// The unified Agent projection for `records`, rebuilt only when the records
    /// differ from the cached ones.
    func projection(for records: [AIToolRecord]) -> AIAgentProjection {
        if let cachedProjection, projectionRecords == records {
            return cachedProjection
        }
        let projection = AIAgentProjection(records: records)
        projectionRecords = records
        cachedProjection = projection
        return projection
    }

    /// Allocated sizes for every Agent's data/config roots, merged into one
    /// path-keyed table. Computed in a single pass over `items` (one path
    /// canonicalisation per item, reused across Agents) and cached against the
    /// snapshot identity.
    func storageSizes(
        snapshotID: UUID,
        items: [ScannedItem],
        agents: [AIAgentEntry]
    ) -> [String: Int64] {
        let key = StorageKey(
            snapshotID: snapshotID,
            itemCount: items.count,
            agentIDs: agents.map(\.id).sorted()
        )
        if storageKey == key { return cachedStorageSizes }

        let perAgent = AIAgentDetailProjection.storageSizes(items: items, forAgents: agents)
        var merged: [String: Int64] = [:]
        for sizes in perAgent.values {
            for (path, size) in sizes {
                merged[path] = size
            }
        }
        storageKey = key
        cachedStorageSizes = merged
        return merged
    }

    /// Per-Agent allocated sizes split by semantic `ItemCategory`, keyed by Agent
    /// id. Same one-pass canonicalisation and snapshot-identity caching as
    /// `storageSizes`, so the detail pane's space-breakdown chart is cheap to
    /// re-render.
    func storageSizesByCategory(
        snapshotID: UUID,
        items: [ScannedItem],
        agents: [AIAgentEntry]
    ) -> [String: [ItemCategory: Int64]] {
        let key = StorageKey(
            snapshotID: snapshotID,
            itemCount: items.count,
            agentIDs: agents.map(\.id).sorted()
        )
        if categoryKey == key { return cachedCategorySizes }

        let perAgent = AIAgentDetailProjection.storageSizesByCategory(items: items, forAgents: agents)
        categoryKey = key
        cachedCategorySizes = perAgent
        return perAgent
    }

    // MARK: - Grouped skill / plugin projections

    private var skillsKey: GroupedKey?
    private var cachedSkillsProjection: GroupedSkillsProjection?
    private var pluginsKey: GroupedKey?
    private var cachedPluginsProjection: GroupedPluginsProjection?

    /// Identity of a grouped projection's inputs. Record ids are stable UUIDs, so
    /// comparing them (plus the discovered tool ids that drive grouping) detects
    /// every input change without deep-comparing whole records.
    private struct GroupedKey: Equatable {
        let skillIDs: [UUID]
        let pluginIDs: [UUID]
        let toolIDs: [String]
    }

    /// Grouped skills for the Global Skills page. Rebuilt only when its inputs
    /// change: the page reads this projection once per rendered row (for the
    /// scope label), so recomputing it per access is what made the page slow.
    func groupedSkills(
        skills: [SkillRecord],
        plugins: [PluginRecord],
        discoveredToolIDs: Set<String>
    ) -> GroupedSkillsProjection {
        let key = GroupedKey(
            skillIDs: skills.map(\.id),
            pluginIDs: plugins.map(\.id),
            toolIDs: discoveredToolIDs.sorted()
        )
        if let cachedSkillsProjection, skillsKey == key { return cachedSkillsProjection }
        let projection = GroupedSkillsProjection(
            skills: skills,
            plugins: plugins,
            discoveredToolIDs: discoveredToolIDs
        )
        skillsKey = key
        cachedSkillsProjection = projection
        return projection
    }

    /// Grouped plugins for the Global Plugins page. Same rationale as
    /// `groupedSkills(skills:plugins:discoveredToolIDs:)`.
    func groupedPlugins(
        plugins: [PluginRecord],
        discoveredToolIDs: Set<String>
    ) -> GroupedPluginsProjection {
        let key = GroupedKey(
            skillIDs: [],
            pluginIDs: plugins.map(\.id),
            toolIDs: discoveredToolIDs.sorted()
        )
        if let cachedPluginsProjection, pluginsKey == key { return cachedPluginsProjection }
        let projection = GroupedPluginsProjection(
            plugins: plugins,
            discoveredToolIDs: discoveredToolIDs
        )
        pluginsKey = key
        cachedPluginsProjection = projection
        return projection
    }
}
