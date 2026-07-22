import Foundation

public struct AppSnapshotProjection: Sendable {
    public let snapshotID: UUID
    public let overview: OverviewProjection
    public let storage: StorageProjection
    public let applications: ApplicationListProjection
    public let developerAI: DeveloperAIProjection

    public init(snapshot: ScanSnapshot) {
        snapshotID = snapshot.id
        overview = OverviewProjection(snapshot: snapshot)
        storage = StorageProjection(snapshot: snapshot)
        applications = ApplicationListProjection(snapshot: snapshot, searchText: "")
        developerAI = DeveloperAIProjection(snapshot: snapshot)
    }
}

public struct AIApplicationProjection: Identifiable, Sendable {
    public var id: UUID { application.id }
    public let application: AIApplicationRecord
    public let totalSize: Int64
    public let dataItems: [ScannedItem]
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]
}

public struct DeveloperAIProjection: Sendable {
    public let developerBytes: Int64
    public let applications: [AIApplicationProjection]
    public let pluginDiagnostics: [String]

    public init(snapshot: ScanSnapshot) {
        let pluginsByID = snapshot.plugins.reduce(into: [UUID: PluginRecord]()) { result, plugin in
            result[plugin.id] = plugin
        }
        let skillsByID = snapshot.skills.reduce(into: [UUID: SkillRecord]()) { result, skill in
            result[skill.id] = skill
        }

        var applicationIDByItemID: [UUID: UUID] = [:]
        for application in snapshot.aiApplications {
            for itemID in application.itemIDs {
                applicationIDByItemID[itemID] = application.id
            }
        }

        var developerItemBytes: Int64 = 0
        var dataItemsByApplicationID: [UUID: [ScannedItem]] = [:]
        for item in snapshot.items {
            if item.category == .developer {
                developerItemBytes += item.allocatedSize
            }
            if let applicationID = applicationIDByItemID[item.id] {
                dataItemsByApplicationID[applicationID, default: []].append(item)
            }
        }

        developerBytes = developerItemBytes
        applications = snapshot.aiApplications.map { application in
            let dataItems = dataItemsByApplicationID[application.id, default: []]
                .sorted { $0.allocatedSize > $1.allocatedSize }
            let plugins = application.pluginIDs.compactMap { pluginsByID[$0] }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let skills = application.skillIDs.compactMap { skillsByID[$0] }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let standaloneSkillBytes = skills.reduce(Int64(0)) { total, skill in
                guard let parentPluginID = skill.parentPluginID else {
                    return total + skill.allocatedSize
                }
                return application.pluginIDs.contains(parentPluginID)
                    ? total
                    : total + skill.allocatedSize
            }
            let totalSize = application.applicationAllocatedSize
                + dataItems.reduce(Int64(0)) { $0 + $1.allocatedSize }
                + plugins.reduce(Int64(0)) { $0 + $1.allocatedSize }
                + standaloneSkillBytes
            return AIApplicationProjection(
                application: application,
                totalSize: totalSize,
                dataItems: dataItems,
                plugins: plugins,
                skills: skills
            )
        }
        pluginDiagnostics = snapshot.pluginDiagnostics ?? []
    }
}
