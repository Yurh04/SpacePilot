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
        managementStatus: SkillManagementStatus
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
    }
}
