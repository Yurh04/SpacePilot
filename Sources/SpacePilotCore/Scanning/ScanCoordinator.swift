import Foundation

public typealias ScanEventEmitter = @Sendable (ScanEvent) -> Void
public typealias ScanOperation = @Sendable (ScanEventEmitter) async throws -> ScanSnapshot
public typealias ScopedScanOperation = @Sendable (ScanScope, ScanEventEmitter) async throws -> ScanSnapshot

public enum ScanScope: String, Codable, Sendable {
    case applications
    case developerAI
    case full
}

public protocol ScanCoordinating: Sendable {
    func scan(scope: ScanScope) -> AsyncThrowingStream<ScanEvent, Error>
}

public struct ScanCoordinator: ScanCoordinating, Sendable {
    private let operation: ScopedScanOperation

    public init(operation: @escaping ScanOperation) {
        self.operation = { _, emit in
            try await operation(emit)
        }
    }

    public init(scopedOperation: @escaping ScopedScanOperation) {
        self.operation = scopedOperation
    }

    public static func live() throws -> ScanCoordinator {
        try SpacePilotRuntime.live().coordinator
    }

    public init(
        homeDirectory: URL,
        store: any SnapshotStoring,
        identityReader: any ApplicationIdentityReading = ApplicationIdentityReader()
    ) {
        self.operation = { scope, emit in
            let previousSnapshot = scope == .full
                ? nil
                : try await store.latestSnapshot()
            let volume = try VolumeScanner().scan()
            let appLocations = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appending(path: "Applications", directoryHint: .isDirectory)
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
            let applicationScanner = ApplicationScanner()
            let baseApplications = try await applicationScanner.scan(locations: appLocations)
            var identities: [ApplicationIdentity] = []
            identities.reserveCapacity(baseApplications.count)
            for application in baseApplications {
                try Task.checkCancellation()
                do {
                    identities.append(try identityReader.read(application: application))
                } catch {
                    identities.append(ApplicationIdentity(
                        applicationID: application.id,
                        mainBundleIdentifier: application.bundleIdentifier,
                        componentBundleIdentifiers: [],
                        teamIdentifier: nil,
                        applicationGroups: []
                    ))
                }
            }
            let quickSnapshot = previousSnapshot ?? ScanSnapshot(
                    completedAt: .now,
                    volume: volume,
                    items: [],
                    applications: baseApplications,
                    aiApplications: [],
                    plugins: [],
                    skills: [],
                    coverage: .complete,
                    pluginDiagnostics: nil
                )
            emit(ScanEvent(
                stage: .quickInventory,
                progress: 0.18,
                message: "Found \(baseApplications.count) applications",
                snapshot: quickSnapshot
            ))

            try Task.checkCancellation()
            if scope == .applications {
                let applicationResolution = try await ApplicationArtifactResolver().resolve(
                    applications: baseApplications,
                    identities: identities,
                    homeDirectory: homeDirectory
                )
                let previousAssociationItemIDs = Set(
                    previousSnapshot?.applications
                        .flatMap(\.associations)
                        .map(\.itemID) ?? []
                )
                let preservedItems = previousSnapshot?.items.filter {
                    !previousAssociationItemIDs.contains($0.id)
                } ?? []
                let canonicalOwnership = try Self.canonicalOwnership(
                    sourceItems: preservedItems + applicationResolution.items,
                    aggregateItems: applicationResolution.items
                )
                let associationsByApplicationID = Dictionary(
                    applicationResolution.resolutions.map { resolution in
                        (
                            resolution.applicationID,
                            resolution.associations.map {
                                Self.remap(
                                    association: $0,
                                    itemIDs: canonicalOwnership.itemIDBySourceItemID
                                )
                            }
                        )
                    },
                    uniquingKeysWith: { first, _ in first }
                )
                let applications = baseApplications.map { application in
                    ApplicationRecord(
                        id: application.id,
                        name: application.name,
                        bundleIdentifier: application.bundleIdentifier,
                        version: application.version,
                        url: application.url,
                        executableURL: application.executableURL,
                        allocatedSize: application.allocatedSize,
                        lastUsedDate: application.lastUsedDate,
                        associations: associationsByApplicationID[
                            application.id,
                            default: []
                        ]
                    )
                }
                let snapshot = ScanSnapshot(
                    completedAt: .now,
                    volume: volume,
                    items: canonicalOwnership.items,
                    applications: applications,
                    aiApplications: previousSnapshot?.aiApplications ?? [],
                    plugins: previousSnapshot?.plugins ?? [],
                    skills: previousSnapshot?.skills ?? [],
                    coverage: previousSnapshot?.coverage ?? .complete,
                    pluginDiagnostics: previousSnapshot?.pluginDiagnostics,
                    categoryAggregates: Self.categoryAggregates(
                        items: canonicalOwnership.items,
                        homeResult: nil,
                        previous: previousSnapshot
                    )
                ).compacted()
                try await store.save(snapshot: snapshot)
                emit(ScanEvent(
                    stage: .completed,
                    progress: 1,
                    message: "Application refresh complete",
                    snapshot: snapshot
                ))
                return snapshot
            }

            async let codexScan = CodexAdapter().scan(homeDirectory: homeDirectory)
            async let claudeScan = ClaudeAdapter().scan(homeDirectory: homeDirectory)
            async let standaloneSkillScan = SkillScanner().scan(roots: SkillRoot.production(homeDirectory: homeDirectory))

            let homeResult: DirectoryScanResult
            if scope == .full {
                homeResult = try await DirectoryScanner(access: LocalFileSystemAccess()).scan(
                    root: homeDirectory,
                    options: DirectoryScanOptions(
                        category: .personal,
                        risk: .sensitive,
                        skipPackages: true,
                        retainedItemLimit: 2_000
                    )
                )
            } else {
                homeResult = DirectoryScanResult(
                    root: homeDirectory,
                    items: previousSnapshot?.items.filter {
                        $0.category == .personal
                            || $0.category == .system
                            || $0.category == .unclassified
                    } ?? [],
                    coverage: previousSnapshot?.coverage ?? .complete
                )
            }
            let (codex, claude, standaloneSkills) = try await (
                codexScan, claudeScan, standaloneSkillScan
            )
            let developer = try await DeveloperStorageScanner().scan(homeDirectory: homeDirectory)
            var basicAIScans: [AIApplicationScanResult] = []
            for definition in BasicAIApplicationDefinition.standard {
                let matchedApplication = baseApplications.first {
                    definition.bundleIdentifiers.contains($0.bundleIdentifier ?? "")
                        || $0.name.localizedCaseInsensitiveContains(definition.name)
                }
                let result = try await BasicAIApplicationScanner().scan(
                    name: definition.name,
                    bundleIdentifier: matchedApplication?.bundleIdentifier ?? definition.bundleIdentifiers.first,
                    homeDirectory: homeDirectory,
                    relativeRoots: definition.relativeRoots
                )
                guard matchedApplication != nil || !result.application.rootURLs.isEmpty else { continue }
                let application = AIApplicationRecord(
                    id: result.application.id,
                    name: result.application.name,
                    bundleIdentifier: result.application.bundleIdentifier,
                    applicationURL: matchedApplication?.url,
                    rootURLs: result.application.rootURLs,
                    itemIDs: result.application.itemIDs,
                    pluginIDs: [],
                    skillIDs: [],
                    applicationAllocatedSize: matchedApplication?.allocatedSize ?? 0,
                    supportLevel: .basic
                )
                basicAIScans.append(AIApplicationScanResult(application: application, items: result.items))
            }
            emit(ScanEvent(stage: .targetedAnalysis, progress: 0.62, message: "Analyzed storage and AI data"))
            try Task.checkCancellation()

            let pluginDiscovery = PluginRootDiscovery(access: LocalFileSystemAccess())
                .discover(homeDirectory: homeDirectory)
            let pluginResult = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: pluginDiscovery.roots)
            let indexedSkills = SkillConflictDetector().detect(in: standaloneSkills + pluginResult.skills)

            let resolver = ApplicationArtifactResolver()
            let applicationResolution = try await resolver.resolve(
                applications: baseApplications,
                identities: identities,
                homeDirectory: homeDirectory
            )

            let sourceItems = homeResult.items
                + developer.items
                + codex.items
                + claude.items
                + basicAIScans.flatMap(\.items)
                + applicationResolution.items
            let canonicalOwnership = try Self.canonicalOwnership(
                sourceItems: sourceItems,
                aggregateItems: applicationResolution.items
            )
            let items = canonicalOwnership.items
            let canonicalItemIDBySourceItemID =
                canonicalOwnership.itemIDBySourceItemID
            let associationsByApplicationID = Dictionary(
                applicationResolution.resolutions.map { resolution in
                    (
                        resolution.applicationID,
                        resolution.associations.map {
                            Self.remap(
                                association: $0,
                                itemIDs: canonicalItemIDBySourceItemID
                            )
                        }
                    )
                },
                uniquingKeysWith: { first, _ in first }
            )
            let applications = baseApplications.map { application in
                ApplicationRecord(
                    id: application.id,
                    name: application.name,
                    bundleIdentifier: application.bundleIdentifier,
                    version: application.version,
                    url: application.url,
                    executableURL: application.executableURL,
                    allocatedSize: application.allocatedSize,
                    lastUsedDate: application.lastUsedDate,
                    associations: associationsByApplicationID[
                        application.id,
                        default: []
                    ]
                )
            }
            let codexSkills = Set(indexedSkills.filter { $0.visibleAgents.contains("Codex") }.map(\.id))
            let claudeSkills = Set(indexedSkills.filter { $0.visibleAgents.contains("Claude") }.map(\.id))
            let codexBundle = baseApplications.first {
                $0.bundleIdentifier == codex.application.bundleIdentifier
                    || $0.name.localizedCaseInsensitiveContains("Codex")
            }
            let claudeBundle = baseApplications.first {
                $0.bundleIdentifier == claude.application.bundleIdentifier
                    || $0.name.localizedCaseInsensitiveContains("Claude")
            }
            let codexApplication = AIApplicationRecord(
                id: codex.application.id,
                name: codex.application.name,
                bundleIdentifier: codex.application.bundleIdentifier,
                applicationURL: codexBundle?.url,
                rootURLs: codex.application.rootURLs,
                itemIDs: Self.remap(
                    itemIDs: codex.application.itemIDs,
                    using: canonicalItemIDBySourceItemID
                ),
                pluginIDs: Set(pluginResult.plugins.map(\.id)),
                skillIDs: codexSkills,
                applicationAllocatedSize: codexBundle?.allocatedSize ?? codex.application.applicationAllocatedSize,
                supportLevel: codex.application.supportLevel
            )
            let claudeApplication = AIApplicationRecord(
                id: claude.application.id,
                name: claude.application.name,
                bundleIdentifier: claude.application.bundleIdentifier,
                applicationURL: claudeBundle?.url,
                rootURLs: claude.application.rootURLs,
                itemIDs: Self.remap(
                    itemIDs: claude.application.itemIDs,
                    using: canonicalItemIDBySourceItemID
                ),
                pluginIDs: [],
                skillIDs: claudeSkills,
                applicationAllocatedSize: claudeBundle?.allocatedSize ?? claude.application.applicationAllocatedSize,
                supportLevel: claude.application.supportLevel
            )
            let basicAIApplications = basicAIScans.map {
                Self.remap(
                    application: $0.application,
                    itemIDs: canonicalItemIDBySourceItemID
                )
            }
            let aiApplications = [codexApplication, claudeApplication]
                + basicAIApplications
            emit(ScanEvent(stage: .indexing, progress: 0.88, message: "Saving local metadata index"))
            try Task.checkCancellation()

            let snapshot = ScanSnapshot(
                completedAt: .now,
                volume: volume,
                items: items,
                applications: applications,
                aiApplications: aiApplications,
                plugins: pluginResult.plugins,
                skills: indexedSkills,
                coverage: homeResult.coverage,
                pluginDiagnostics: pluginDiscovery.diagnostics.map(\.message) + pluginResult.diagnostics,
                categoryAggregates: Self.categoryAggregates(
                    items: items,
                    homeResult: scope == .full ? homeResult : nil,
                    previous: previousSnapshot
                )
            ).compacted()
            try await store.save(snapshot: snapshot)
            emit(ScanEvent(stage: .completed, progress: 1, message: "Scan complete", snapshot: snapshot))
            return snapshot
        }
    }

    public func scan(scope: ScanScope = .full) -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await operation(scope) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func collectScan(scope: ScanScope = .full) async throws -> ScanSnapshot {
        var completed: ScanSnapshot?
        for try await event in scan(scope: scope) {
            if let snapshot = event.snapshot { completed = snapshot }
        }
        guard let completed else { throw CancellationError() }
        return completed
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func categoryAggregates(
        items: [ScannedItem],
        homeResult: DirectoryScanResult?,
        previous: ScanSnapshot?
    ) -> [CategoryAggregate] {
        var totals: [ItemCategory: (bytes: Int64, count: Int)] = [:]
        for item in items where item.category != .personal {
            totals[item.category, default: (0, 0)].bytes += item.allocatedSize
            totals[item.category, default: (0, 0)].count += 1
        }

        if let homeResult {
            let canonicalHome = canonicalPath(for: homeResult.root)
            let reassignedBytes = items.lazy.filter {
                guard $0.category != .personal else { return false }
                let path = canonicalPath(for: $0.url)
                return path == canonicalHome || path.hasPrefix(canonicalHome + "/")
            }.reduce(Int64(0)) { $0 + $1.allocatedSize }
            totals[.personal] = (
                max(0, homeResult.totalAllocatedSize - reassignedBytes),
                homeResult.fileCount
            )
        } else if let previousPersonal = previous?.categoryAggregates?.first(where: {
            $0.category == .personal
        }) {
            totals[.personal] = (
                previousPersonal.allocatedSize,
                previousPersonal.itemCount
            )
        } else {
            let personalItems = items.filter { $0.category == .personal }
            totals[.personal] = (
                personalItems.reduce(Int64(0)) { $0 + $1.allocatedSize },
                personalItems.count
            )
        }

        return totals.map {
            CategoryAggregate(
                category: $0.key,
                allocatedSize: $0.value.bytes,
                itemCount: $0.value.count
            )
        }.sorted { $0.category.rawValue < $1.category.rawValue }
    }

    private static func canonicalOwnership(
        sourceItems: [ScannedItem],
        aggregateItems: [ScannedItem]
    ) throws -> CanonicalItemOwnership {
        var checkpoint = ProjectionCancellationCheckpoint {
            try Task.checkCancellation()
        }
        var exactItemByPath: [String: ScannedItem] = [:]
        exactItemByPath.reserveCapacity(sourceItems.count)
        for item in sourceItems {
            try checkpoint.checkPeriodically()
            exactItemByPath[canonicalPath(for: item.url)] = item
        }

        var aggregateItemByPath: [String: ScannedItem] = [:]
        aggregateItemByPath.reserveCapacity(aggregateItems.count)
        for aggregateItem in aggregateItems {
            try checkpoint.checkPeriodically()
            guard let values = try? aggregateItem.url.resourceValues(
                forKeys: [.isDirectoryKey]
            ), values.isDirectory == true
            else {
                continue
            }
            let path = canonicalPath(for: aggregateItem.url)
            guard exactItemByPath[path] != nil else {
                continue
            }
            aggregateItemByPath[path] = aggregateItem
        }

        let orderedAggregates = aggregateItemByPath.sorted {
            let lhsDepth = URL(fileURLWithPath: $0.key).pathComponents.count
            let rhsDepth = URL(fileURLWithPath: $1.key).pathComponents.count
            if lhsDepth != rhsDepth {
                return lhsDepth < rhsDepth
            }
            return $0.key < $1.key
        }
        var survivingAggregateByPath: [String: ScannedItem] = [:]
        survivingAggregateByPath.reserveCapacity(orderedAggregates.count)
        for (path, item) in orderedAggregates {
            try checkpoint.checkPeriodically()
            guard nearestAncestorItem(
                of: path,
                in: survivingAggregateByPath
            ) == nil else {
                continue
            }
            survivingAggregateByPath[path] = item
        }

        var items: [ScannedItem] = []
        items.reserveCapacity(exactItemByPath.count)
        var survivorItemIDByPath: [String: UUID] = [:]
        survivorItemIDByPath.reserveCapacity(exactItemByPath.count)
        for (path, item) in exactItemByPath {
            try checkpoint.checkPeriodically()
            if let aggregateItem = survivingAggregateByPath[path] {
                items.append(aggregateItem)
                survivorItemIDByPath[path] = aggregateItem.id
            } else if let aggregateItem = nearestAncestorItem(
                of: path,
                in: survivingAggregateByPath
            ) {
                survivorItemIDByPath[path] = aggregateItem.id
            } else {
                items.append(item)
                survivorItemIDByPath[path] = item.id
            }
        }

        var itemIDBySourceItemID: [UUID: UUID] = [:]
        itemIDBySourceItemID.reserveCapacity(sourceItems.count)
        for item in sourceItems {
            try checkpoint.checkPeriodically()
            let path = canonicalPath(for: item.url)
            guard let survivorID = survivorItemIDByPath[path] else {
                continue
            }
            itemIDBySourceItemID[item.id] = survivorID
        }
        try Task.checkCancellation()
        return CanonicalItemOwnership(
            items: items.sorted { $0.url.path < $1.url.path },
            itemIDBySourceItemID: itemIDBySourceItemID
        )
    }

    private static func nearestAncestorItem(
        of path: String,
        in itemsByPath: [String: ScannedItem]
    ) -> ScannedItem? {
        var ancestor = URL(fileURLWithPath: path).deletingLastPathComponent()
        while true {
            let ancestorPath = ancestor.path
            if let item = itemsByPath[ancestorPath] {
                return item
            }
            let parent = ancestor.deletingLastPathComponent()
            guard parent.path != ancestorPath else {
                return nil
            }
            ancestor = parent
        }
    }

    private static func remap(
        association: ArtifactAssociation,
        itemIDs: [UUID: UUID]
    ) -> ArtifactAssociation {
        ArtifactAssociation(
            id: association.id,
            itemID: itemIDs[association.itemID] ?? association.itemID,
            applicationID: association.applicationID,
            evidence: association.evidence,
            confidence: association.confidence,
            risk: association.risk,
            ownership: association.ownership
        )
    }

    private static func remap(
        itemIDs: Set<UUID>,
        using replacements: [UUID: UUID]
    ) -> Set<UUID> {
        Set(itemIDs.map { replacements[$0] ?? $0 })
    }

    private static func remap(
        application: AIApplicationRecord,
        itemIDs: [UUID: UUID]
    ) -> AIApplicationRecord {
        AIApplicationRecord(
            id: application.id,
            name: application.name,
            bundleIdentifier: application.bundleIdentifier,
            applicationURL: application.applicationURL,
            rootURLs: application.rootURLs,
            itemIDs: remap(
                itemIDs: application.itemIDs,
                using: itemIDs
            ),
            pluginIDs: application.pluginIDs,
            skillIDs: application.skillIDs,
            applicationAllocatedSize: application.applicationAllocatedSize,
            supportLevel: application.supportLevel
        )
    }

    private struct CanonicalItemOwnership {
        let items: [ScannedItem]
        let itemIDBySourceItemID: [UUID: UUID]
    }
}

private struct BasicAIApplicationDefinition: Sendable {
    let name: String
    let bundleIdentifiers: [String]
    let relativeRoots: [String]

    static let standard: [Self] = [
        .init(
            name: "ChatGPT",
            bundleIdentifiers: ["com.openai.chat"],
            relativeRoots: [
                "Library/Application Support/com.openai.chat",
                "Library/Application Support/ChatGPT",
                "Library/Caches/com.openai.chat"
            ]
        ),
        .init(
            name: "Ollama",
            bundleIdentifiers: ["com.electron.ollama"],
            relativeRoots: [".ollama", "Library/Application Support/Ollama"]
        ),
        .init(
            name: "OpenCode",
            bundleIdentifiers: [],
            relativeRoots: [".local/share/opencode", ".config/opencode", ".cache/opencode"]
        )
    ]
}
