import Foundation

public enum AIAssetGroupKind: Hashable, Sendable {
    case sharedGlobal
    case toolGlobal(definitionID: String)
    case toolProject(definitionID: String, project: AIProjectIdentity)
    case toolBundled(definitionID: String)
    case toolSystem(definitionID: String)
    case unknown
}

public struct AIAssetGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let kind: AIAssetGroupKind
    public let title: String
    public let detail: String
    public let itemCount: Int
    public let allocatedSize: Int64

    public init(
        id: String,
        kind: AIAssetGroupKind,
        title: String,
        detail: String,
        itemCount: Int,
        allocatedSize: Int64
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.itemCount = itemCount
        self.allocatedSize = allocatedSize
    }
}

public struct GroupedSkillsProjection: Sendable {
    public let groups: [AIAssetGroup]
    private let recordsByGroupID: [String: [SkillRecord]]

    public init(
        skills: [SkillRecord],
        plugins: [PluginRecord],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) {
        let pluginOwnerByID = Dictionary(uniqueKeysWithValues: plugins.map { ($0.id, $0.owner) })
        let records = Self.deduplicated(skills)
        let grouped = Dictionary(grouping: records) { skill in
            Self.groupKey(for: skill, pluginOwnerByID: pluginOwnerByID)
        }
        let orderedKeys = Self.orderedKeys(Array(grouped.keys), definitions: definitions)
        let definitionNames = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.displayName) })
        self.groups = orderedKeys.map { key in
            let records = grouped[key, default: []]
            return key.group(records: records, definitionNames: definitionNames)
        }
        self.recordsByGroupID = Dictionary(uniqueKeysWithValues: orderedKeys.map { key in
            (key.id, (grouped[key] ?? []).sorted(by: Self.recordOrder))
        })
    }

    public func skills(in groupID: String, matching query: String = "") -> [SkillRecord] {
        filter(recordsByGroupID[groupID] ?? [], query: query)
    }

    public static func resolvedSelection(
        current: String?,
        preferredOwnerFrom previous: String?,
        groups: [AIAssetGroup]
    ) -> String? {
        if let current, groups.contains(where: { $0.id == current }) { return current }
        if let previousOwner = previous.flatMap(ownerPrefix),
           let nearest = groups.first(where: { ownerPrefix($0.id) == previousOwner }) {
            return nearest.id
        }
        return groups.first?.id
    }

    private static func groupKey(
        for skill: SkillRecord,
        pluginOwnerByID: [UUID: AIAssetOwner]
    ) -> AIAssetGroupKey {
        if case .plugin = skill.owner {
            guard let pluginID = skill.parentPluginID,
                  case .tool(let definitionID) = pluginOwnerByID[pluginID] else {
                return .unknown
            }
            return .tool(definitionID: definitionID, scope: .bundled)
        }
        return AIAssetGroupKey(owner: skill.owner, locationScope: skill.locationScope)
    }

    private static func deduplicated(_ records: [SkillRecord]) -> [SkillRecord] {
        Dictionary(grouping: records, by: { DedupKey(url: $0.url, owner: $0.owner, locationScope: $0.locationScope) })
            .values
            .compactMap { $0.sorted(by: recordOrder).first }
            .sorted(by: recordOrder)
    }

    private static func orderedKeys(_ keys: [AIAssetGroupKey], definitions: [AIToolDefinition]) -> [AIAssetGroupKey] {
        AIAssetGroupKey.ordered(keys, definitions: definitions)
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

    public init(
        plugins: [PluginRecord],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) {
        let records = Self.deduplicated(plugins)
        let grouped = Dictionary(grouping: records) { AIAssetGroupKey(owner: $0.owner, locationScope: $0.locationScope) }
        let orderedKeys = AIAssetGroupKey.ordered(Array(grouped.keys), definitions: definitions)
        let definitionNames = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0.displayName) })
        self.groups = orderedKeys.map { key in
            let records = grouped[key, default: []]
            return key.group(records: records, definitionNames: definitionNames)
        }
        self.recordsByGroupID = Dictionary(uniqueKeysWithValues: orderedKeys.map { key in
            (key.id, (grouped[key] ?? []).sorted(by: Self.recordOrder))
        })
    }

    public func plugins(in groupID: String, matching query: String = "") -> [PluginRecord] {
        filter(recordsByGroupID[groupID] ?? [], query: query)
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

private struct DedupKey: Hashable {
    let canonicalPath: String
    let owner: AIAssetOwner
    let locationScope: AIAssetLocationScope

    init(url: URL, owner: AIAssetOwner, locationScope: AIAssetLocationScope) {
        self.canonicalPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        self.owner = owner
        self.locationScope = locationScope
    }
}

private enum AIAssetGroupKey: Hashable {
    case sharedGlobal
    case tool(definitionID: String, scope: ToolScope)
    case unknown

    enum ToolScope: Hashable {
        case global
        case project(AIProjectIdentity)
        case bundled
        case system
    }

    init(owner: AIAssetOwner, locationScope: AIAssetLocationScope) {
        switch (owner, locationScope) {
        case (.shared, .userGlobal):
            self = .sharedGlobal
        case (.tool(let definitionID), .userGlobal):
            self = .tool(definitionID: definitionID, scope: .global)
        case (.tool(let definitionID), .project(let project)):
            self = .tool(definitionID: definitionID, scope: .project(project))
        case (.tool(let definitionID), .bundled):
            self = .tool(definitionID: definitionID, scope: .bundled)
        case (.tool(let definitionID), .system):
            self = .tool(definitionID: definitionID, scope: .system)
        default:
            self = .unknown
        }
    }

    var id: String {
        switch self {
        case .sharedGlobal:
            return "shared:global"
        case .tool(let definitionID, let scope):
            return "tool:\(definitionID):\(scope.id)"
        case .unknown:
            return "unknown"
        }
    }

    static func ordered(_ keys: [Self], definitions: [AIToolDefinition]) -> [Self] {
        let keySet = Set(keys)
        var ordered: [Self] = []
        if keySet.contains(.sharedGlobal) { ordered.append(.sharedGlobal) }
        for definition in definitions {
            let global = Self.tool(definitionID: definition.id, scope: .global)
            if keySet.contains(global) { ordered.append(global) }
            let projects = keySet.compactMap { key -> AIProjectIdentity? in
                guard case .tool(definition.id, .project(let project)) = key else { return nil }
                return project
            }
            for project in projects.sorted(by: projectOrder) {
                ordered.append(.tool(definitionID: definition.id, scope: .project(project)))
            }
            for scope in [ToolScope.bundled, .system] {
                let key = Self.tool(definitionID: definition.id, scope: scope)
                if keySet.contains(key) { ordered.append(key) }
            }
        }
        let known = Set(ordered)
        ordered.append(contentsOf: keySet.subtracting(known).filter { $0 != .unknown }.sorted(by: fallbackOrder))
        if keySet.contains(.unknown) { ordered.append(.unknown) }
        return ordered
    }

    func group<Record>(records: [Record], definitionNames: [String: String]) -> AIAssetGroup where Record: AIAssetGroupRecord {
        AIAssetGroup(
            id: id,
            kind: kind,
            title: title(definitionNames: definitionNames),
            detail: detail,
            itemCount: records.count,
            allocatedSize: records.reduce(0) { $0 + $1.allocatedSize }
        )
    }

    private var kind: AIAssetGroupKind {
        switch self {
        case .sharedGlobal:
            return .sharedGlobal
        case .tool(let definitionID, .global):
            return .toolGlobal(definitionID: definitionID)
        case .tool(let definitionID, .project(let project)):
            return .toolProject(definitionID: definitionID, project: project)
        case .tool(let definitionID, .bundled):
            return .toolBundled(definitionID: definitionID)
        case .tool(let definitionID, .system):
            return .toolSystem(definitionID: definitionID)
        case .unknown:
            return .unknown
        }
    }

    private func title(definitionNames: [String: String]) -> String {
        switch self {
        case .sharedGlobal:
            return "Shared"
        case .tool(let definitionID, let scope):
            let name = definitionNames[definitionID] ?? definitionID
            switch scope {
            case .global, .bundled, .system:
                return name
            case .project(let project):
                return project.displayName
            }
        case .unknown:
            return "Unknown"
        }
    }

    private var detail: String {
        switch self {
        case .sharedGlobal:
            return "Global"
        case .tool(_, .global):
            return "Global"
        case .tool(_, .project):
            return "Project"
        case .tool(_, .bundled):
            return "Bundled"
        case .tool(_, .system):
            return "System"
        case .unknown:
            return "Unattributed"
        }
    }

    private static func projectOrder(_ lhs: AIProjectIdentity, _ rhs: AIProjectIdentity) -> Bool {
        let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return lhs.id < rhs.id
    }

    private static func fallbackOrder(_ lhs: Self, _ rhs: Self) -> Bool {
        lhs.id < rhs.id
    }
}

private extension AIAssetGroupKey.ToolScope {
    var id: String {
        switch self {
        case .global:
            return "global"
        case .project(let project):
            return "project:\(project.id)"
        case .bundled:
            return "bundled"
        case .system:
            return "system"
        }
    }
}

private protocol AIAssetGroupRecord {
    var allocatedSize: Int64 { get }
}

extension SkillRecord: AIAssetGroupRecord {}
extension PluginRecord: AIAssetGroupRecord {}

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
    let lhsPath = lhsURL.standardizedFileURL.resolvingSymlinksInPath().path
    let rhsPath = rhsURL.standardizedFileURL.resolvingSymlinksInPath().path
    if lhsPath != rhsPath { return lhsPath < rhsPath }
    return lhsID < rhsID
}

private func ownerPrefix(_ groupID: String) -> String? {
    if groupID == "shared:global" { return "shared" }
    if groupID == "unknown" { return "unknown" }
    let parts = groupID.split(separator: ":", maxSplits: 2).map(String.init)
    guard parts.count >= 2 else { return nil }
    return parts[0] + ":" + parts[1]
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
