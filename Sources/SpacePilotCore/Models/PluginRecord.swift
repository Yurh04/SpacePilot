import Foundation

public enum PluginManagementCapability: String, Codable, Sendable {
    case inspectOnly
    case officialHandoff
}

public struct PluginRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let version: String?
    public let url: URL
    public let source: String
    public let allocatedSize: Int64
    public let skillIDs: Set<UUID>
    public let dependencies: [String]
    public let managementCapability: PluginManagementCapability
    public let owner: AIAssetOwner
    public let locationScope: AIAssetLocationScope

    public var skillCount: Int { skillIDs.count }

    public init(
        id: UUID = UUID(),
        name: String,
        version: String?,
        url: URL,
        source: String,
        allocatedSize: Int64,
        skillIDs: Set<UUID> = [],
        dependencies: [String] = [],
        managementCapability: PluginManagementCapability = .officialHandoff,
        owner: AIAssetOwner = .unknown,
        locationScope: AIAssetLocationScope = .userGlobal
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.url = url
        self.source = source
        self.allocatedSize = allocatedSize
        self.skillIDs = skillIDs
        self.dependencies = dependencies
        self.managementCapability = managementCapability
        self.owner = owner
        self.locationScope = locationScope
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case url
        case source
        case allocatedSize
        case skillIDs
        case dependencies
        case managementCapability
        case owner
        case locationScope
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        url = try container.decode(URL.self, forKey: .url)
        source = try container.decode(String.self, forKey: .source)
        allocatedSize = try container.decode(Int64.self, forKey: .allocatedSize)
        skillIDs = try container.decodeIfPresent(Set<UUID>.self, forKey: .skillIDs) ?? []
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        managementCapability = try container.decodeIfPresent(
            PluginManagementCapability.self,
            forKey: .managementCapability
        ) ?? .officialHandoff
        owner = try container.decodeIfPresent(AIAssetOwner.self, forKey: .owner) ?? .unknown
        locationScope = try container.decodeIfPresent(AIAssetLocationScope.self, forKey: .locationScope)
            ?? .userGlobal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encode(url, forKey: .url)
        try container.encode(source, forKey: .source)
        try container.encode(allocatedSize, forKey: .allocatedSize)
        try container.encode(skillIDs, forKey: .skillIDs)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(managementCapability, forKey: .managementCapability)
        try container.encode(owner, forKey: .owner)
        try container.encode(locationScope, forKey: .locationScope)
    }
}
