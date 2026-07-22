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

    public init(
        id: UUID = UUID(),
        name: String,
        version: String?,
        url: URL,
        source: String,
        allocatedSize: Int64,
        skillIDs: Set<UUID> = [],
        dependencies: [String] = [],
        managementCapability: PluginManagementCapability = .officialHandoff
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
    }
}
