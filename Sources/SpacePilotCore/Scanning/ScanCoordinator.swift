import Foundation

public typealias ScanEventEmitter = @Sendable (ScanEvent) -> Void
public typealias ScanOperation = @Sendable (ScanEventEmitter) async throws -> ScanSnapshot

public protocol ScanCoordinating: Sendable {
    func scan() -> AsyncThrowingStream<ScanEvent, Error>
}

public struct ScanCoordinator: ScanCoordinating, Sendable {
    private let operation: ScanOperation

    public init(operation: @escaping ScanOperation) {
        self.operation = operation
    }

    public static func live() throws -> ScanCoordinator {
        try SpacePilotRuntime.live().coordinator
    }

    public init(
        homeDirectory: URL,
        store: any SnapshotStoring,
        identityReader: any ApplicationIdentityReading = ApplicationIdentityReader()
    ) {
        self.operation = { emit in
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
            let quickSnapshot = ScanSnapshot(
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
            async let homeScan = DirectoryScanner(access: LocalFileSystemAccess()).scan(
                root: homeDirectory,
                options: DirectoryScanOptions(category: .personal, risk: .sensitive, skipPackages: true)
            )
            async let codexScan = CodexAdapter().scan(homeDirectory: homeDirectory)
            async let claudeScan = ClaudeAdapter().scan(homeDirectory: homeDirectory)
            async let standaloneSkillScan = SkillScanner().scan(roots: SkillRoot.production(homeDirectory: homeDirectory))

            let (homeResult, codex, claude, standaloneSkills) = try await (
                homeScan, codexScan, claudeScan, standaloneSkillScan
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
            var itemsByPath: [String: ScannedItem] = [:]
            for item in sourceItems {
                itemsByPath[Self.canonicalPath(for: item.url)] = item
            }
            let items = itemsByPath.values.sorted { $0.url.path < $1.url.path }
            let canonicalItemIDBySourceItemID = Dictionary(
                sourceItems.compactMap { item -> (UUID, UUID)? in
                    guard let canonicalItem = itemsByPath[
                        Self.canonicalPath(for: item.url)
                    ] else {
                        return nil
                    }
                    return (item.id, canonicalItem.id)
                },
                uniquingKeysWith: { _, latest in latest }
            )
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
                pluginDiagnostics: pluginDiscovery.diagnostics.map(\.message) + pluginResult.diagnostics
            )
            try await store.save(snapshot: snapshot)
            emit(ScanEvent(stage: .completed, progress: 1, message: "Scan complete", snapshot: snapshot))
            return snapshot
        }
    }

    public func scan() -> AsyncThrowingStream<ScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await operation { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func collectScan() async throws -> ScanSnapshot {
        var completed: ScanSnapshot?
        for try await event in scan() {
            if let snapshot = event.snapshot { completed = snapshot }
        }
        guard let completed else { throw CancellationError() }
        return completed
    }

    private static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
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
