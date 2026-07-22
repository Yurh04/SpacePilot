import Foundation

public enum AIApplicationSupportLevel: String, Codable, Sendable {
    case deep
    case basic
}

public struct AIApplicationRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String?
    public let applicationURL: URL?
    public let rootURLs: [URL]
    public let itemIDs: Set<UUID>
    public let pluginIDs: Set<UUID>
    public let skillIDs: Set<UUID>
    public let applicationAllocatedSize: Int64
    public let supportLevel: AIApplicationSupportLevel

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String?,
        applicationURL: URL?,
        rootURLs: [URL],
        itemIDs: Set<UUID>,
        pluginIDs: Set<UUID>,
        skillIDs: Set<UUID>,
        applicationAllocatedSize: Int64,
        supportLevel: AIApplicationSupportLevel
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.rootURLs = rootURLs
        self.itemIDs = itemIDs
        self.pluginIDs = pluginIDs
        self.skillIDs = skillIDs
        self.applicationAllocatedSize = applicationAllocatedSize
        self.supportLevel = supportLevel
    }
}
