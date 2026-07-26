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

public struct CategoryAggregate: Codable, Hashable, Sendable {
    public let category: ItemCategory
    public let allocatedSize: Int64
    public let itemCount: Int

    public init(category: ItemCategory, allocatedSize: Int64, itemCount: Int) {
        self.category = category
        self.allocatedSize = max(0, allocatedSize)
        self.itemCount = max(0, itemCount)
    }
}

public struct ScanSnapshot: Identifiable, Codable, Sendable {
    public static let maximumRetainedItems = 10_000

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
    public let categoryAggregates: [CategoryAggregate]?

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
        pluginDiagnostics: [String]? = nil,
        categoryAggregates: [CategoryAggregate]? = nil
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
        self.categoryAggregates = categoryAggregates
    }

    public var uniqueAIAllocatedSize: Int64 {
        let directSize = aiApplications.reduce(Int64(0)) { $0 + $1.applicationAllocatedSize }
        let itemIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.itemIDs) }
        let pluginIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.pluginIDs) }
        let skillIDs = aiApplications.reduce(into: Set<UUID>()) { $0.formUnion($1.skillIDs) }
        return AIAssetByteOwnership.aggregate(
            applicationBytes: directSize,
            items: items.lazy.filter { itemIDs.contains($0.id) },
            plugins: plugins.lazy.filter { pluginIDs.contains($0.id) },
            skills: skills.lazy.filter { skillIDs.contains($0.id) },
            ownedPluginIDs: pluginIDs
        ).total
    }

    public func mergingAIProductFamilies() -> ScanSnapshot {
        let mergedAIApplications = AIApplicationProductFamilyMerger()
            .mergeChatGPTAndCodex(in: aiApplications)
        guard mergedAIApplications != aiApplications else { return self }

        return ScanSnapshot(
            id: id,
            completedAt: completedAt,
            volume: volume,
            items: items,
            applications: applications,
            aiApplications: mergedAIApplications,
            plugins: plugins,
            skills: skills,
            coverage: coverage,
            pluginDiagnostics: pluginDiagnostics,
            categoryAggregates: categoryAggregates
        )
    }

    public func compacted(
        retainedItemLimit: Int = Self.maximumRetainedItems
    ) -> ScanSnapshot {
        let limit = max(0, retainedItemLimit)
        guard items.count > limit else { return self }

        let referencedItemIDs = Set(
            applications.flatMap(\.associations).map(\.itemID)
                + aiApplications.flatMap { Array($0.itemIDs) }
        )
        let retainedItems = items.sorted { lhs, rhs in
            let lhsReferenced = referencedItemIDs.contains(lhs.id)
            let rhsReferenced = referencedItemIDs.contains(rhs.id)
            if lhsReferenced != rhsReferenced {
                return lhsReferenced && !rhsReferenced
            }
            if lhs.allocatedSize != rhs.allocatedSize {
                return lhs.allocatedSize > rhs.allocatedSize
            }
            return lhs.url.path < rhs.url.path
        }.prefix(limit)
        let retainedIDs = Set(retainedItems.map(\.id))
        let compactedApplications = applications.map { application in
            ApplicationRecord(
                id: application.id,
                name: application.name,
                bundleIdentifier: application.bundleIdentifier,
                version: application.version,
                url: application.url,
                executableURL: application.executableURL,
                allocatedSize: application.allocatedSize,
                lastUsedDate: application.lastUsedDate,
                associations: application.associations.filter {
                    retainedIDs.contains($0.itemID)
                }
            )
        }
        let compactedAIApplications = aiApplications.map { application in
            AIApplicationRecord(
                id: application.id,
                name: application.name,
                bundleIdentifier: application.bundleIdentifier,
                applicationURL: application.applicationURL,
                rootURLs: application.rootURLs,
                itemIDs: application.itemIDs.intersection(retainedIDs),
                pluginIDs: application.pluginIDs,
                skillIDs: application.skillIDs,
                applicationAllocatedSize: application.applicationAllocatedSize,
                supportLevel: application.supportLevel
            )
        }
        let note = "Retained \(limit) representative items from "
            + "\(items.count) indexed items"
        return ScanSnapshot(
            id: id,
            completedAt: completedAt,
            volume: volume,
            items: Array(retainedItems),
            applications: compactedApplications,
            aiApplications: compactedAIApplications,
            plugins: plugins,
            skills: skills,
            coverage: ScanCoverage(
                deniedPaths: coverage.deniedPaths,
                notes: coverage.notes + [note]
            ),
            pluginDiagnostics: pluginDiagnostics,
            categoryAggregates: categoryAggregates
        )
    }
}
