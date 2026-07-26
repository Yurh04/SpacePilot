import Foundation

public struct AppSnapshotProjection: Sendable {
    public let snapshotID: UUID
    public let overview: OverviewProjection
    public let storage: StorageProjection
    public let applications: ApplicationListProjection
    public let developerAI: DeveloperAIProjection

    public init(snapshot: ScanSnapshot) {
        let snapshot = snapshot.mergingAIProductFamilies()
        self.init(
            snapshotID: snapshot.id,
            overview: OverviewProjection(snapshot: snapshot),
            storage: StorageProjection(snapshot: snapshot),
            applications: ApplicationListProjection(snapshot: snapshot, searchText: ""),
            developerAI: DeveloperAIProjection(snapshot: snapshot)
        )
    }

    public static func build(snapshot: ScanSnapshot) throws -> Self {
        let checkCancellation: @Sendable () throws -> Void = {
            try Task.checkCancellation()
        }
        return try build(snapshot: snapshot, checkCancellation: checkCancellation)
    }

    static func build(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws -> Self {
        try checkCancellation()
        let snapshot = snapshot.mergingAIProductFamilies()
        let overview = try OverviewProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let storage = try StorageProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let applications = try ApplicationListProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        let developerAI = try DeveloperAIProjection(
            snapshot: snapshot,
            checkCancellation: checkCancellation
        )
        try checkCancellation()
        return Self(
            snapshotID: snapshot.id,
            overview: overview,
            storage: storage,
            applications: applications,
            developerAI: developerAI
        )
    }

    private init(
        snapshotID: UUID,
        overview: OverviewProjection,
        storage: StorageProjection,
        applications: ApplicationListProjection,
        developerAI: DeveloperAIProjection
    ) {
        self.snapshotID = snapshotID
        self.overview = overview
        self.storage = storage
        self.applications = applications
        self.developerAI = developerAI
    }
}

public struct AIApplicationProjection: Identifiable, Sendable {
    public var id: UUID { application.id }
    public let application: AIApplicationRecord
    public let totalSize: Int64
    public let dataItems: [ScannedItem]
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]

    public init(
        application: AIApplicationRecord,
        totalSize: Int64,
        dataItems: [ScannedItem],
        plugins: [PluginRecord],
        skills: [SkillRecord]
    ) {
        self.application = application
        self.totalSize = totalSize
        self.dataItems = dataItems
        self.plugins = plugins
        self.skills = skills
    }
}

public struct AIApplicationQueryProjection: Sendable {
    public let applicationID: UUID
    public let query: String
    public let dataItems: [ScannedItem]
    public let skills: [SkillRecord]

    public static func build(
        application: AIApplicationProjection,
        query: String
    ) throws -> Self {
        try Task.checkCancellation()
        guard !query.isEmpty else {
            let result = Self(
                applicationID: application.id,
                query: query,
                dataItems: application.dataItems,
                skills: application.skills
            )
            try Task.checkCancellation()
            return result
        }

        var checkpoint = ProjectionCancellationCheckpoint {
            try Task.checkCancellation()
        }
        var dataItems: [ScannedItem] = []
        for item in application.dataItems {
            try checkpoint.checkPeriodically()
            if item.url.path.localizedCaseInsensitiveContains(query) {
                dataItems.append(item)
            }
        }
        var skills: [SkillRecord] = []
        for skill in application.skills {
            try checkpoint.checkPeriodically()
            if skill.name.localizedCaseInsensitiveContains(query) {
                skills.append(skill)
            }
        }
        let result = Self(
            applicationID: application.id,
            query: query,
            dataItems: dataItems,
            skills: skills
        )
        try Task.checkCancellation()
        return result
    }
}

public struct DeveloperAIProjection: Sendable {
    public let developerBytes: Int64
    public let applications: [AIApplicationProjection]
    public let pluginDiagnostics: [String]

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        try checkCancellation()
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var pluginsByID: [UUID: PluginRecord] = [:]
        for plugin in snapshot.plugins {
            try checkpoint.checkPeriodically()
            pluginsByID[plugin.id] = plugin
        }
        var skillsByID: [UUID: SkillRecord] = [:]
        for skill in snapshot.skills {
            try checkpoint.checkPeriodically()
            skillsByID[skill.id] = skill
        }

        var applicationIDByItemID: [UUID: UUID] = [:]
        for application in snapshot.aiApplications {
            try checkpoint.checkPeriodically()
            for itemID in application.itemIDs {
                try checkpoint.checkPeriodically()
                applicationIDByItemID[itemID] = application.id
            }
        }

        var developerItemBytes: Int64 = 0
        var dataItemsByApplicationID: [UUID: [ScannedItem]] = [:]
        for item in snapshot.items {
            try checkpoint.checkPeriodically()
            if item.category == .developer {
                developerItemBytes += item.allocatedSize
            }
            if let applicationID = applicationIDByItemID[item.id] {
                dataItemsByApplicationID[applicationID, default: []].append(item)
            }
        }

        developerBytes = developerItemBytes
        var applicationProjections: [AIApplicationProjection] = []
        applicationProjections.reserveCapacity(snapshot.aiApplications.count)
        for application in snapshot.aiApplications {
            try checkpoint.checkPeriodically()
            let dataItems = try ProjectionCancellationAwareOrdering.sorted(
                dataItemsByApplicationID[application.id, default: []],
                by: { $0.allocatedSize > $1.allocatedSize },
                checkCancellation: checkCancellation
            )

            var unorderedPlugins: [PluginRecord] = []
            unorderedPlugins.reserveCapacity(application.pluginIDs.count)
            for pluginID in application.pluginIDs {
                try checkpoint.checkPeriodically()
                if let plugin = pluginsByID[pluginID] {
                    unorderedPlugins.append(plugin)
                }
            }
            let plugins = try ProjectionCancellationAwareOrdering.sorted(
                unorderedPlugins,
                by: {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                checkCancellation: checkCancellation
            )

            var unorderedSkills: [SkillRecord] = []
            unorderedSkills.reserveCapacity(application.skillIDs.count)
            for skillID in application.skillIDs {
                try checkpoint.checkPeriodically()
                if let skill = skillsByID[skillID] {
                    unorderedSkills.append(skill)
                }
            }
            let skills = try ProjectionCancellationAwareOrdering.sorted(
                unorderedSkills,
                by: {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                },
                checkCancellation: checkCancellation
            )

            let byteBreakdown = try AIAssetByteOwnership.aggregate(
                applicationBytes: application.applicationAllocatedSize,
                items: dataItems,
                plugins: plugins,
                skills: skills,
                ownedPluginIDs: application.pluginIDs,
                checkCancellation: checkCancellation
            )
            applicationProjections.append(AIApplicationProjection(
                application: application,
                totalSize: byteBreakdown.total,
                dataItems: dataItems,
                plugins: plugins,
                skills: skills
            ))
            try checkCancellation()
        }
        applications = applicationProjections
        pluginDiagnostics = snapshot.pluginDiagnostics ?? []
        try checkCancellation()
    }
}
