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
        let home = FileManager.default.homeDirectoryForCurrentUser
        let databaseURL = home.appending(path: "Library/Application Support/SpacePilot/index.sqlite")
        let store = try SQLiteIndexStore(url: databaseURL)
        return ScanCoordinator(homeDirectory: home, store: store)
    }

    public init(homeDirectory: URL, store: any SnapshotStoring) {
        self.operation = { emit in
            let volume = try VolumeScanner().scan()
            let appLocations = [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                homeDirectory.appending(path: "Applications", directoryHint: .isDirectory)
            ].filter { FileManager.default.fileExists(atPath: $0.path) }
            let applicationScanner = ApplicationScanner()
            let baseApplications = try await applicationScanner.scan(locations: appLocations)
            emit(ScanEvent(
                stage: .quickInventory,
                progress: 0.18,
                message: "Found \(baseApplications.count) applications"
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
            emit(ScanEvent(stage: .targetedAnalysis, progress: 0.62, message: "Analyzed storage and AI data"))
            try Task.checkCancellation()

            let pluginRoots = discoverPluginRoots(homeDirectory: homeDirectory)
            let pluginResult = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: pluginRoots)
            let indexedSkills = SkillConflictDetector().detect(in: standaloneSkills + pluginResult.skills)

            var applicationItems: [ScannedItem] = []
            var applications: [ApplicationRecord] = []
            let resolver = ApplicationArtifactResolver()
            for application in baseApplications {
                try Task.checkCancellation()
                let resolution = try await resolver.resolve(application: application, homeDirectory: homeDirectory)
                applicationItems.append(contentsOf: resolution.items)
                applications.append(ApplicationRecord(
                    id: application.id,
                    name: application.name,
                    bundleIdentifier: application.bundleIdentifier,
                    version: application.version,
                    url: application.url,
                    executableURL: application.executableURL,
                    allocatedSize: application.allocatedSize,
                    lastUsedDate: application.lastUsedDate,
                    associations: resolution.associations
                ))
            }

            var itemsByPath = Dictionary(uniqueKeysWithValues: homeResult.items.map { ($0.url.path, $0) })
            for item in applicationItems + codex.items + claude.items {
                itemsByPath[item.url.path] = item
            }
            let items = itemsByPath.values.sorted { $0.url.path < $1.url.path }
            let aiApplications = [codex.application, claude.application]
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
                coverage: homeResult.coverage
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
}

private func discoverPluginRoots(homeDirectory: URL) -> [URL] {
    let cache = homeDirectory.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
    guard let enumerator = FileManager.default.enumerator(
        at: cache,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsPackageDescendants]
    ) else { return [] }
    var roots = Set<URL>()
    for case let url as URL in enumerator where url.lastPathComponent == "plugin.json" {
        let manifestDirectory = url.deletingLastPathComponent()
        guard manifestDirectory.lastPathComponent == ".codex-plugin" else { continue }
        roots.insert(manifestDirectory.deletingLastPathComponent().standardizedFileURL)
    }
    return roots.sorted { $0.path < $1.path }
}
