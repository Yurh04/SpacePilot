import Foundation

public enum SkillScope: Codable, Hashable, Sendable {
    case sharedAgents
    case agentSpecific(agent: String)
    case pluginProvided(pluginID: String)
    case systemManaged
}

public enum SkillManagementStatus: String, Codable, Sendable {
    case standalone
    case parentManaged
    case systemReadOnly
}

public enum SkillConflict: String, Codable, Sendable {
    case exactDuplicate
    case sameNameDifferentContent
    case agentOverride
}

public struct SkillRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let summary: String
    public let url: URL
    public let allocatedSize: Int64
    public let scope: SkillScope
    public let visibleAgents: Set<String>
    public let parentPluginID: UUID?
    public let fingerprint: String
    public let conflict: SkillConflict?
    public let managementStatus: SkillManagementStatus
    public let owner: AIAssetOwner
    public let locationScope: AIAssetLocationScope

    public init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        url: URL,
        allocatedSize: Int64,
        scope: SkillScope,
        visibleAgents: Set<String>,
        parentPluginID: UUID?,
        fingerprint: String,
        conflict: SkillConflict?,
        managementStatus: SkillManagementStatus,
        owner: AIAssetOwner? = nil,
        locationScope: AIAssetLocationScope? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.url = url
        self.allocatedSize = allocatedSize
        self.scope = scope
        self.visibleAgents = visibleAgents
        self.parentPluginID = parentPluginID
        self.fingerprint = fingerprint
        self.conflict = conflict
        self.managementStatus = managementStatus
        self.owner = owner ?? AIAssetOwner.migrated(from: scope)
        self.locationScope = locationScope ?? AIAssetLocationScope.migrated(from: scope)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case url
        case allocatedSize
        case scope
        case visibleAgents
        case parentPluginID
        case fingerprint
        case conflict
        case managementStatus
        case owner
        case locationScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let scope = try container.decode(SkillScope.self, forKey: .scope)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        summary = try container.decode(String.self, forKey: .summary)
        url = try container.decode(URL.self, forKey: .url)
        allocatedSize = try container.decode(Int64.self, forKey: .allocatedSize)
        self.scope = scope
        visibleAgents = try container.decode(Set<String>.self, forKey: .visibleAgents)
        parentPluginID = try container.decodeIfPresent(UUID.self, forKey: .parentPluginID)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        conflict = try container.decodeIfPresent(SkillConflict.self, forKey: .conflict)
        managementStatus = try container.decode(SkillManagementStatus.self, forKey: .managementStatus)
        owner = try container.decodeIfPresent(AIAssetOwner.self, forKey: .owner)
            ?? AIAssetOwner.migrated(from: scope)
        locationScope = try container.decodeIfPresent(AIAssetLocationScope.self, forKey: .locationScope)
            ?? AIAssetLocationScope.migrated(from: scope)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(summary, forKey: .summary)
        try container.encode(url, forKey: .url)
        try container.encode(allocatedSize, forKey: .allocatedSize)
        try container.encode(scope, forKey: .scope)
        try container.encode(visibleAgents, forKey: .visibleAgents)
        try container.encodeIfPresent(parentPluginID, forKey: .parentPluginID)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encodeIfPresent(conflict, forKey: .conflict)
        try container.encode(managementStatus, forKey: .managementStatus)
        try container.encode(owner, forKey: .owner)
        try container.encode(locationScope, forKey: .locationScope)
    }
}
