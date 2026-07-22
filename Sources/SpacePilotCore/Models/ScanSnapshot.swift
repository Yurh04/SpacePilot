import Foundation

public struct VolumeRecord: Codable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let totalCapacity: Int64
    public let availableCapacity: Int64

    public init(url: URL, name: String, totalCapacity: Int64, availableCapacity: Int64) {
        self.url = url
        self.name = name
        self.totalCapacity = totalCapacity
        self.availableCapacity = availableCapacity
    }
}

public struct ScanCoverage: Codable, Hashable, Sendable {
    public let deniedPaths: [URL]
    public let notes: [String]

    public init(deniedPaths: [URL] = [], notes: [String] = []) {
        self.deniedPaths = deniedPaths
        self.notes = notes
    }

    public static let complete = ScanCoverage()
    public var isComplete: Bool { deniedPaths.isEmpty }
}

public struct ScanSnapshot: Identifiable, Codable, Sendable {
    public let id: UUID
    public let completedAt: Date
    public let volume: VolumeRecord?
    public let items: [ScannedItem]
    public let applications: [ApplicationRecord]
    public let aiApplications: [AIApplicationRecord]
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]
    public let coverage: ScanCoverage
    public let pluginDiagnostics: [String]?

    public init(
        id: UUID = UUID(),
        completedAt: Date,
        volume: VolumeRecord?,
        items: [ScannedItem],
        applications: [ApplicationRecord],
        aiApplications: [AIApplicationRecord],
        plugins: [PluginRecord],
        skills: [SkillRecord],
        coverage: ScanCoverage,
        pluginDiagnostics: [String]? = nil
    ) {
        self.id = id
        self.completedAt = completedAt
        self.volume = volume
        self.items = items
        self.applications = applications
        self.aiApplications = aiApplications
        self.plugins = plugins
        self.skills = skills
        self.coverage = coverage
        self.pluginDiagnostics = pluginDiagnostics
    }

    public var uniqueAIAllocatedSize: Int64 {
        let directSize = aiApplications.reduce(Int64(0)) { $0 + $1.applicationAllocatedSize }
        let itemIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.itemIDs) }
        let pluginIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.pluginIDs) }
        let skillIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.skillIDs) }
        let itemSize = items.lazy.filter { itemIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let pluginSize = plugins.lazy.filter { pluginIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.allocatedSize }
        let skillSize = skills.lazy
            .filter {
                guard skillIDs.contains($0.id) else { return false }
                guard let parentPluginID = $0.parentPluginID else { return true }
                return !pluginIDs.contains(parentPluginID)
            }
            .reduce(Int64(0)) { $0 + $1.allocatedSize }
        return directSize + itemSize + pluginSize + skillSize
    }
}
