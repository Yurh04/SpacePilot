import Foundation

/// First-level ownership grouping. The sidebar shows one entry per AI tool that
/// actually has assets, a single "Shared" entry (assets shared by every AI), and
/// an "Unknown" entry only when unattributed assets exist. Location scope
/// (userGlobal / project / bundled / system) is NOT a sidebar level anymore; it
/// is surfaced per-row in the right pane via `scopeDetail(for:)`.
public enum AIAssetGroupKind: Hashable, Sendable {
    case shared
    case tool(definitionID: String)
    case unknown
}

public struct AIAssetGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: AIAssetGroupKind
    public let title: String
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(
        id: String,
        kind: AIAssetGroupKind,
        title: String,
        itemCount: Int,
        allocatedSize: Int64
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

/// Canonical, non-localized location-scope descriptor for a right-pane row. The
/// UI layer localizes these tokens; Core never emits localized strings.
public enum AIAssetScopeDetail: Hashable, Sendable {
    case global
    case project(AIProjectIdentity)
    case bundled
    case system
    case unattributed
}

public struct GroupedSkillsProjection: Sendable {
    public let groups: [AIAssetGroup]
    private let recordsByGroupID: [String: [SkillRecord]]
    private let scopeDetailByRecordID: [UUID: AIAssetScopeDetail]

    public init(
        skills: [SkillRecord],
        plugins: [PluginRecord],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all,
        discoveredToolIDs: Set<String> = []
    ) {
        let pluginScopeByID = Dictionary(uniqueKeysWithValues: plugins.map {
            ($0.id, PluginGroupingScope(owner: $0.owner, locationScope: $0.locationScope))
        })
        let records = Self.deduplicated(skills)
        let resolved = records.map { skill -> (SkillRecord, OwnerKey, AIAssetScopeDetail) in
            let (ownerKey, scope) = Self.attribution(for: skill, pluginScopeByID: pluginScopeByID)
            return (skill, ownerKey, scope)
        }
        let grouped = Dictionary(grouping: resolved) { $0.1 }
        let orderedKeys = OwnerKey.ordered(
            Array(grouped.keys),
            definitions: definitions,
            discoveredToolIDs: discoveredToolIDs
        )
        let definitionNames = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.displayName) })
        self.groups = orderedKeys.map { key in
            let items = grouped[key, default: []]
            return key.group(
                title: key.title(definitionNames: definitionNames),
                itemCount: items.count,
                allocatedSize: items.reduce(0) { $0 + $1.0.allocatedSize }
            )
        }
        self.recordsByGroupID = Dictionary(uniqueKeysWithValues: orderedKeys.map { key in
            (key.id, (grouped[key] ?? []).map(\.0).sorted(by: Self.recordOrder))
        })
        self.scopeDetailByRecordID = Dictionary(
            resolved.map { ($0.0.id, $0.2) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func skills(in groupID: String, matching query: String = "") -> [SkillRecord] {
        filter(recordsByGroupID[groupID] ?? [], query: query)
    }

    public func scopeDetail(for skill: SkillRecord) -> AIAssetScopeDetail {
        scopeDetailByRecordID[skill.id] ?? .unattributed
    }

    public static func resolvedSelection(
        current: String?,
        preferredOwnerFrom previous: String?,
        groups: [AIAssetGroup]
    ) -> String? {
        if let current, groups.contains(where: { $0.id == current }) { return current }
        if let previous, let nearest = groups.first(where: { $0.id == previous }) {
            return nearest.id
        }
        return groups.first?.id
    }

    private static func attribution(
        for skill: SkillRecord,
        pluginScopeByID: [UUID: PluginGroupingScope]
    ) -> (OwnerKey, AIAssetScopeDetail) {
        if case .plugin = skill.owner {
            guard let pluginID = skill.parentPluginID,
                  let pluginScope = pluginScopeByID[pluginID],
                  case .tool(let definitionID) = pluginScope.owner else {
                return (.unknown, scopeDetail(for: skill.locationScope))
            }
            // A plugin-provided skill aggregates to its parent plugin's tool
            // owner. Its scope follows the parent plugin: a project plugin keeps
            // the skill in that project, otherwise it is bundled.
            switch pluginScope.locationScope {
            case .project(let project):
                return (.tool(definitionID: definitionID), .project(project))
            default:
                return (.tool(definitionID: definitionID), .bundled)
            }
        }
        return (OwnerKey(owner: skill.owner), scopeDetail(for: skill.locationScope))
    }

    private static func scopeDetail(for location: AIAssetLocationScope) -> AIAssetScopeDetail {
        switch location {
        case .userGlobal: .global
        case .project(let project): .project(project)
        case .bundled: .bundled
        case .system: .system
        }
    }

    private static func deduplicated(_ records: [SkillRecord]) -> [SkillRecord] {
        Dictionary(grouping: records, by: { DedupKey(url: $0.url, owner: $0.owner, locationScope: $0.locationScope) })
            .values
            .compactMap { $0.sorted(by: recordOrder).first }
            .sorted(by: recordOrder)
    }

    private static func recordOrder(_ lhs: SkillRecord, _ rhs: SkillRecord) -> Bool {
        totalOrder(
            lhsName: lhs.name,
            lhsURL: lhs.url,
            lhsID: lhs.id.uuidString,
            rhsName: rhs.name,
            rhsURL: rhs.url,
            rhsID: rhs.id.uuidString
        )
    }
}

public struct GroupedPluginsProjection: Sendable {
    public let groups: [AIAssetGroup]
    private let recordsByGroupID: [String: [PluginRecord]]
    private let scopeDetailByRecordID: [UUID: AIAssetScopeDetail]

    public init(
        plugins: [PluginRecord],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all,
        discoveredToolIDs: Set<String> = []
    ) {
        let records = Self.deduplicated(plugins)
        let resolved = records.map { plugin -> (PluginRecord, OwnerKey, AIAssetScopeDetail) in
            (plugin, OwnerKey(owner: plugin.owner), GroupedSkillsProjection.scopeDetailPublic(plugin.locationScope))
        }
        let grouped = Dictionary(grouping: resolved) { $0.1 }
        let orderedKeys = OwnerKey.ordered(
            Array(grouped.keys),
            definitions: definitions,
            discoveredToolIDs: discoveredToolIDs
        )
        let definitionNames = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.displayName) })
        self.groups = orderedKeys.map { key in
            let items = grouped[key, default: []]
            return key.group(
                title: key.title(definitionNames: definitionNames),
                itemCount: items.count,
                allocatedSize: items.reduce(0) { $0 + $1.0.allocatedSize }
            )
        }
        self.recordsByGroupID = Dictionary(uniqueKeysWithValues: orderedKeys.map { key in
            (key.id, (grouped[key] ?? []).map(\.0).sorted(by: Self.recordOrder))
        })
        self.scopeDetailByRecordID = Dictionary(
            resolved.map { ($0.0.id, $0.2) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func plugins(in groupID: String, matching query: String = "") -> [PluginRecord] {
        filter(recordsByGroupID[groupID] ?? [], query: query)
    }

    public func scopeDetail(for plugin: PluginRecord) -> AIAssetScopeDetail {
        scopeDetailByRecordID[plugin.id] ?? .unattributed
    }

    public static func resolvedSelection(
        current: String?,
        preferredOwnerFrom previous: String?,
        groups: [AIAssetGroup]
    ) -> String? {
        GroupedSkillsProjection.resolvedSelection(current: current, preferredOwnerFrom: previous, groups: groups)
    }

    private static func deduplicated(_ records: [PluginRecord]) -> [PluginRecord] {
        Dictionary(grouping: records, by: { DedupKey(url: $0.url, owner: $0.owner, locationScope: $0.locationScope) })
            .values
            .compactMap { $0.sorted(by: recordOrder).first }
            .sorted(by: recordOrder)
    }

    private static func recordOrder(_ lhs: PluginRecord, _ rhs: PluginRecord) -> Bool {
        totalOrder(
            lhsName: lhs.name,
            lhsURL: lhs.url,
            lhsID: lhs.id.uuidString,
            rhsName: rhs.name,
            rhsURL: rhs.url,
            rhsID: rhs.id.uuidString
        )
    }
}

extension GroupedSkillsProjection {
    // Shared with the plugins projection so both use one scope-detail mapping.
    static func scopeDetailPublic(_ location: AIAssetLocationScope) -> AIAssetScopeDetail {
        scopeDetail(for: location)
    }
}

private struct DedupKey: Hashable {
    let canonicalPath: String
    let owner: AIAssetOwner
    let locationScope: AIAssetLocationScope

    init(url: URL, owner: AIAssetOwner, locationScope: AIAssetLocationScope) {
        self.canonicalPath = url.canonicalizedDiscoveryPath
        self.owner = owner
        self.locationScope = locationScope
    }
}

private struct PluginGroupingScope: Hashable {
    let owner: AIAssetOwner
    let locationScope: AIAssetLocationScope
}

/// Owner-level grouping key. Location scope is intentionally excluded so the
/// first level collapses to Shared / one entry per tool / Unknown.
private enum OwnerKey: Hashable {
    case shared
    case tool(definitionID: String)
    case unknown

    init(owner: AIAssetOwner) {
        switch owner {
        case .shared:
            self = .shared
        case .tool(let definitionID):
            self = .tool(definitionID: definitionID)
        case .plugin, .unknown:
            self = .unknown
        }
    }

    var id: String {
        switch self {
        case .shared: "shared"
        case .tool(let definitionID): "tool:\(definitionID)"
        case .unknown: "unknown"
        }
    }

    var kind: AIAssetGroupKind {
        switch self {
        case .shared: .shared
        case .tool(let definitionID): .tool(definitionID: definitionID)
        case .unknown: .unknown
        }
    }

    /// Produces the ordered sidebar keys. `discoveredToolIDs` seeds an entry for
    /// each AI that was discovered (installed app / CLI / tool-owned asset) even
    /// when it currently has zero skills/plugins, so the sidebar reflects the
    /// machine rather than only owners present in records. Shared is always the
    /// first row; Unknown appears only when a genuinely unattributed asset
    /// exists. Ordering follows catalog order with a stable id fallback and is
    /// independent of input order.
    static func ordered(
        _ keys: [Self],
        definitions: [AIToolDefinition],
        discoveredToolIDs: Set<String> = []
    ) -> [Self] {
        var keySet = Set(keys)
        for toolID in discoveredToolIDs {
            keySet.insert(.tool(definitionID: toolID))
        }
        var ordered: [Self] = []
        if keySet.contains(.shared) { ordered.append(.shared) }
        for definition in definitions {
            let key = Self.tool(definitionID: definition.id)
            if keySet.contains(key) { ordered.append(key) }
        }
        let known = Set(ordered)
        let remainingTools = keySet
            .subtracting(known)
            .filter { $0 != .unknown }
            .sorted { $0.id < $1.id }
        ordered.append(contentsOf: remainingTools)
        if keySet.contains(.unknown) { ordered.append(.unknown) }
        return ordered
    }

    func group(title: String, itemCount: Int, allocatedSize: Int64) -> AIAssetGroup {
        AIAssetGroup(
            id: id,
            kind: kind,
            title: title,
            itemCount: itemCount,
            allocatedSize: allocatedSize
        )
    }

    func title(definitionNames: [String: String]) -> String {
        switch self {
        case .shared: "Shared"
        case .tool(let definitionID): definitionNames[definitionID] ?? definitionID
        case .unknown: "Unknown"
        }
    }
}

private func totalOrder(
    lhsName: String,
    lhsURL: URL,
    lhsID: String,
    rhsName: String,
    rhsURL: URL,
    rhsID: String
) -> Bool {
    let nameOrder = lhsName.localizedCaseInsensitiveCompare(rhsName)
    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
    let lhsPath = lhsURL.canonicalizedDiscoveryPath
    let rhsPath = rhsURL.canonicalizedDiscoveryPath
    if lhsPath != rhsPath { return lhsPath < rhsPath }
    return lhsID < rhsID
}

private func filter(_ skills: [SkillRecord], query: String) -> [SkillRecord] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return skills }
    return skills.filter {
        $0.name.localizedCaseInsensitiveContains(query)
            || $0.summary.localizedCaseInsensitiveContains(query)
            || $0.url.path.localizedCaseInsensitiveContains(query)
    }
}

private func filter(_ plugins: [PluginRecord], query: String) -> [PluginRecord] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return plugins }
    return plugins.filter {
        $0.name.localizedCaseInsensitiveContains(query)
            || ($0.version?.localizedCaseInsensitiveContains(query) ?? false)
            || $0.source.localizedCaseInsensitiveContains(query)
            || $0.url.path.localizedCaseInsensitiveContains(query)
    }
}
