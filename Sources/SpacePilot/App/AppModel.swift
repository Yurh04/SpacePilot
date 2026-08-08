import AppKit
import Foundation
import Observation
import OSLog
import SpacePilotCore
import UniformTypeIdentifiers

@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "com.yurunhao.SpacePilot", category: "runtime")
    var selection: NavigationDestination? = .overview {
        didSet { refreshAIQueryProjection() }
    }
    var searchText = "" {
        didSet { refreshAIQueryProjection() }
    }
    var selectedAIApplicationID: UUID? {
        didSet { refreshAIQueryProjection() }
    }
    var selectedAIApplicationTab: AIApplicationTab = .overview
    var latestSnapshot: ScanSnapshot?
    var projection: AppSnapshotProjection?
    var aiQueryProjection: AIApplicationQueryProjection?
    var scanStage: ScanStage?
    var scanProgress = 0.0
    var scanMessage = L10n.scanStatus(for: nil)
    var errorMessage: String?
    var isScanning = false
    var isBackgroundRefreshing = false
    var isCleaning = false
    var showingCleanupConfirmation = false
    var cleanupCandidates: [CleanupReviewItem] = []
    var latestCleanupTransaction: CleanupTransaction?
    var cleanupHistory: [CleanupTransaction] = []
    var analyzingApplicationID: UUID?
    /// Read-only projection of discovered AI tools/assets for the future
    /// management UI. Never mutated by discovery directly; only replaced whole.
    var aiManagementProjection = AIManagementProjection.empty
    var isDiscoveringAITools = false
    /// A read-only error surface for AI discovery. Deliberately separate from
    /// `errorMessage` so a discovery failure never clobbers the main scan error.
    var aiDiscoveryError: String?

    var isPreparingAIQuery: Bool {
        guard selection == .developerAI,
              !searchText.isEmpty,
              let selectedAIApplicationID else { return false }
        return aiQueryProjection?.applicationID != selectedAIApplicationID
            || aiQueryProjection?.query != searchText
    }

    var canRefreshCurrentView: Bool {
        selection != .history && !isScanning
    }

    var showsScanStatus: Bool {
        isScanning && !isBackgroundRefreshing
    }

    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var applicationAnalysisTask: Task<Void, Never>?
    private var analyzedApplicationIDs: Set<UUID> = []
    private var cleanupOperationID: UUID?
    private var projectionWorker: Task<AppSnapshotProjection, Error>?
    private var projectionPublicationTask: Task<Void, Never>?
    private var aiQueryWorker: Task<AIApplicationQueryProjection, Error>?
    private var aiQueryPublicationTask: Task<Void, Never>?
    private var fileSystemMonitor: FileSystemChangeMonitor?
    private var fileSystemChangeReconciler: FileSystemChangeReconciler?
    private var pendingAutomaticRefreshScope: ScanScope?
    private let runtime: SpacePilotRuntime?

    // MARK: - AI discovery

    /// Injected discovery function. It receives an immutable snapshot and the
    /// home directory and returns read-only records. It is executed on a
    /// detached, non-MainActor worker; injecting it (rather than calling
    /// `AIToolRegistry` directly) makes publication races deterministically
    /// testable without spawning real processes.
    private let discoverAITools: @Sendable (ScanSnapshot, URL) async throws -> [AIToolRecord]
    /// Home directory used to anchor discovery. In production this mirrors the
    /// runtime's home directory; in tests it is injected directly so discovery
    /// can run without a live runtime.
    private let aiDiscoveryHomeURL: URL?
    /// The off-MainActor worker computing records, and the MainActor task that
    /// awaits it and publishes. Both are cancelled on a new snapshot or explicit
    /// cancellation, mirroring `projectionWorker`/`projectionPublicationTask`.
    private var aiDiscoveryWorker: Task<[AIToolRecord], Error>?
    private var aiDiscoveryPublicationTask: Task<Void, Never>?
    /// Monotonically increasing token; only the newest discovery may publish.
    private var aiDiscoveryGeneration = 0
    /// The fingerprint of the last snapshot whose discovery *successfully
    /// published*. Only a completed, still-current pass sets this, so a failed or
    /// cancelled first pass never suppresses a retry for the same inputs.
    private var lastSuccessfulAIDiscoveryFingerprint: AIDiscoveryFingerprint?
    /// Set when the user explicitly refreshes the Developer & AI view; consumed
    /// by the next `apply(snapshot:)` to force a fresh discovery pass.
    private var pendingForceAIDiscovery = false

    init() {
        do {
            runtime = try .live()
        } catch {
            runtime = nil
            errorMessage = error.localizedDescription
        }
        self.discoverAITools = Self.liveAIToolDiscovery
        self.aiDiscoveryHomeURL = runtime?.homeDirectory
        Task { await loadSavedState() }
    }

    /// Internal initializer used by tests to inject a deterministic discovery
    /// function and skip the live runtime, so publication-race behavior can be
    /// exercised without touching disk or spawning processes.
    init(
        runtime: SpacePilotRuntime?,
        homeDirectory: URL,
        discoverAITools: @escaping @Sendable (ScanSnapshot, URL) async throws -> [AIToolRecord]
    ) {
        self.runtime = runtime
        self.aiDiscoveryHomeURL = homeDirectory
        self.discoverAITools = discoverAITools
    }

    /// The production discovery function: builds a snapshot-backed locator and a
    /// read-only `AIToolRegistry`, then discovers records off the MainActor.
    private static let liveAIToolDiscovery: @Sendable (ScanSnapshot, URL) async throws -> [AIToolRecord] = { snapshot, homeDirectory in
        let locator = SnapshotAIApplicationLocator(snapshot: snapshot)
        let registry = AIToolRegistry(applicationLocator: locator)
        return try await registry.discover(homeDirectory: homeDirectory)
    }

    func startScan(
        scope: ScanScope = .applications,
        background: Bool = false
    ) {
        guard !isScanning, let coordinator = runtime?.coordinator else { return }
        if !background {
            errorMessage = nil
        }
        isScanning = true
        isBackgroundRefreshing = background
        scanTask = Task {
            do {
                for try await event in coordinator.scan(scope: scope) {
                    guard !Task.isCancelled else { break }
                    if event.stage == .completed, scope == .applications {
                        applicationAnalysisTask?.cancel()
                        applicationAnalysisTask = nil
                        analyzingApplicationID = nil
                        analyzedApplicationIDs.removeAll(keepingCapacity: true)
                    }
                    if background {
                        if event.stage == .completed,
                           let snapshot = event.snapshot {
                            apply(snapshot: snapshot)
                        }
                    } else {
                        scanStage = event.stage
                        scanProgress = event.progress
                        scanMessage = event.message
                        if let snapshot = event.snapshot {
                            apply(snapshot: snapshot)
                        }
                    }
                    Self.logger.info("Scan stage: \(event.stage.rawValue, privacy: .public)")
                }
            } catch is CancellationError {
                if !background {
                    scanMessage = L10n.text(.scanCancelled)
                }
            } catch {
                if !background {
                    errorMessage = error.localizedDescription
                }
                Self.logger.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            }
            isScanning = false
            isBackgroundRefreshing = false
            scanTask = nil
            startPendingAutomaticRefreshIfNeeded()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        // A cancelled scan should not leave an in-flight discovery running; the
        // generation bump ensures a mid-flight worker can never publish.
        cancelAIManagementDiscovery()
    }

    func refreshCurrentView() {
        guard canRefreshCurrentView else { return }
        let scope: ScanScope = switch selection ?? .overview {
        case .overview, .storage:
            .full
        case .applications:
            .applications
        case .developerAI:
            .developerAI
        case .history:
            .applications
        }
        if scope == .developerAI {
            // An explicit Developer & AI refresh should re-run discovery even if
            // the AI-relevant snapshot inputs look unchanged.
            pendingForceAIDiscovery = true
        }
        startScan(scope: scope)
    }

    func prepareCleanup(items: [ScannedItem]) {
        let eligible = items
            .filter { $0.risk != .managed }
            .map {
                CleanupReviewItem(item: $0, ownership: .owned, evidence: nil)
            }
        prepareCleanup(reviewItems: eligible)
    }

    private func prepareCleanup(reviewItems: [CleanupReviewItem]) {
        let eligible = reviewItems.filter { $0.effectiveRisk != .managed }
        guard !eligible.isEmpty else { return }
        cleanupCandidates = eligible
        latestCleanupTransaction = nil
        showingCleanupConfirmation = true
    }

    func prepareUninstall(application: ApplicationProjection) {
        let record = application.application
        if let bundleID = record.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            errorMessage = L10n.quitBeforeUninstall(record.name)
            return
        }
        prepareCleanup(
            reviewItems: ApplicationUninstallPlanner().cleanupItems(for: application)
        )
    }

    func prepareReset(application: ApplicationProjection) {
        let items = ApplicationUninstallPlanner().resetItems(for: application)
        guard !items.isEmpty else {
            errorMessage = L10n.resetUnavailable(application.application.name)
            return
        }
        prepareCleanup(items: items)
    }

    func analyzeApplication(_ projection: ApplicationProjection) {
        guard !analyzedApplicationIDs.contains(projection.id),
              analyzingApplicationID != projection.id,
              let runtime,
              let currentSnapshot = latestSnapshot else {
            return
        }
        applicationAnalysisTask?.cancel()
        analyzingApplicationID = projection.id
        let snapshotID = currentSnapshot.id
        let application = projection.application
        applicationAnalysisTask = Task {
            do {
                let analysis = try await ApplicationDetailAnalyzer(
                    directoryStats: runtime.store,
                    cache: runtime.store
                ).analyze(
                    application: application,
                    homeDirectory: runtime.homeDirectory,
                    indexedItems: currentSnapshot.items,
                    indexedAIApplications: currentSnapshot.aiApplications
                )
                guard !Task.isCancelled,
                      latestSnapshot?.id == snapshotID,
                      analyzingApplicationID == application.id,
                      let updated = snapshot(
                          currentSnapshot,
                          applying: analysis
                      ) else {
                    throw CancellationError()
                }
                try await runtime.store.save(snapshot: updated)
                analyzedApplicationIDs.insert(application.id)
                apply(snapshot: updated)
            } catch is CancellationError {
                Self.logger.info("Application detail analysis cancelled")
            } catch {
                if analyzingApplicationID == application.id {
                    errorMessage = error.localizedDescription
                }
                Self.logger.error(
                    "Application detail analysis failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            if analyzingApplicationID == application.id {
                analyzingApplicationID = nil
                applicationAnalysisTask = nil
            }
        }
    }

    func executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool) {
        guard let runtime, let snapshot = latestSnapshot, !isCleaning else { return }
        let candidateItems = cleanupCandidates.map(\.item)
        let candidateIDs = Set(candidateItems.map(\.id))
        let eligibleSelectedIDs = selectedIDs.intersection(candidateIDs)
        let sensitiveCandidateIDs = Set(cleanupCandidates.filter {
            $0.effectiveRisk == .sensitive
        }.map(\.id))
        guard !eligibleSelectedIDs.isEmpty else { return }
        let operationID = UUID()
        cleanupOperationID = operationID
        isCleaning = true
        errorMessage = nil
        cleanupTask = Task {
            do {
                let sensitiveIDs = confirmSensitive
                    ? eligibleSelectedIDs.intersection(sensitiveCandidateIDs)
                    : []
                let policy = PathSafetyPolicy(
                    homeDirectory: runtime.homeDirectory,
                    allowedVolumeRoot: URL(fileURLWithPath: "/", isDirectory: true)
                )
                let planningWorker = Task.detached(priority: .userInitiated) {
                    try CleanupPlanner(policy: policy).makePlan(
                        snapshotID: snapshot.id,
                        items: candidateItems,
                        selectedIDs: eligibleSelectedIDs,
                        separatelyConfirmedSensitiveIDs: sensitiveIDs
                    )
                }
                let plan = try await withTaskCancellationHandler {
                    try await planningWorker.value
                } onCancel: {
                    planningWorker.cancel()
                }
                planningWorker.cancel()
                guard !Task.isCancelled,
                      cleanupOperationID == operationID,
                      latestSnapshot?.id == snapshot.id else {
                    throw CancellationError()
                }
                let transaction = try await CleanupExecutor(
                    policy: policy,
                    mover: FileManagerTrashMover(),
                    store: runtime.store
                ).execute(plan: plan)
                guard !Task.isCancelled,
                      cleanupOperationID == operationID else {
                    throw CancellationError()
                }
                latestCleanupTransaction = transaction
                cleanupHistory = try await runtime.store.cleanupHistory()
                Self.logger.info("Cleanup finished: \(transaction.summary.rawValue, privacy: .public)")
                showingCleanupConfirmation = false
                if let updated = snapshotAfterCleanup(
                    snapshot,
                    plan: plan,
                    transaction: transaction
                ) {
                    try await runtime.store.save(snapshot: updated)
                    apply(snapshot: updated)
                }
            } catch is CancellationError {
                Self.logger.info("Cleanup cancelled")
            } catch {
                if cleanupOperationID == operationID {
                    errorMessage = error.localizedDescription
                    Self.logger.error("Cleanup failed: \(error.localizedDescription, privacy: .public)")
                }
            }
            if cleanupOperationID == operationID {
                isCleaning = false
                cleanupTask = nil
                cleanupOperationID = nil
                startPendingAutomaticRefreshIfNeeded()
            }
        }
    }

    private func loadSavedState() async {
        guard let runtime else { return }
        do {
            if let snapshot = try await runtime.store.latestSnapshot() {
                apply(snapshot: snapshot)
                try await runtime.store.ensureStorageIndex(snapshot: snapshot)
            }
            cleanupHistory = try await runtime.store.cleanupHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            try await startStorageMonitoring(runtime: runtime)
        } catch {
            Self.logger.error(
                "Could not start storage monitoring: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func startStorageMonitoring(
        runtime: SpacePilotRuntime
    ) async throws {
        guard fileSystemMonitor == nil else { return }
        let volumeID = FileSystemChangeMonitor.volumeID(
            for: runtime.homeDirectory
        )
        let cursor = try await runtime.store.fileSystemEventCursor(
            volumeID: volumeID
        )
        if cursor == nil {
            try await runtime.store.markAllDirectoryStatsDirty()
        }

        let indexDirectory = runtime.homeDirectory.appending(
            path: "Library/Application Support/SpacePilot",
            directoryHint: .isDirectory
        )
        let monitor = FileSystemChangeMonitor(
            root: runtime.homeDirectory,
            ignoredRoots: [indexDirectory]
        )
        let store = runtime.store
        let logger = Self.logger
        let homeDirectory = runtime.homeDirectory
        let reconciler = FileSystemChangeReconciler(
            root: homeDirectory
        ) { [weak self] batch in
            do {
                if batch.requiresFullInvalidation {
                    try await store.markAllDirectoryStatsDirty()
                } else if !batch.changedPaths.isEmpty {
                    try await store.markDirectoryStatsDirty(
                        changedPaths: batch.changedPaths
                    )
                }
                if batch.lastEventID > 0 {
                    try await store.save(fileSystemEventCursor: .init(
                        volumeID: volumeID,
                        lastEventID: batch.lastEventID,
                        lastReconciledAt: .now
                    ))
                }
                if let scope = IncrementalRefreshPlanner.scope(
                    for: batch,
                    homeDirectory: homeDirectory
                ) {
                    await self?.requestAutomaticRefresh(scope: scope)
                }
            } catch {
                logger.error(
                    "FSEvents reconciliation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
        let startingEventID = try monitor.start(
            sinceEventID: cursor?.lastEventID
        ) { batch in
            Task {
                await reconciler.submit(batch)
            }
        }
        fileSystemMonitor = monitor
        fileSystemChangeReconciler = reconciler
        if cursor == nil {
            try await store.save(fileSystemEventCursor: .init(
                volumeID: volumeID,
                lastEventID: startingEventID,
                lastReconciledAt: .now
            ))
        }
    }

    private func requestAutomaticRefresh(scope: ScanScope) {
        guard latestSnapshot != nil else { return }
        if isScanning || isCleaning {
            pendingAutomaticRefreshScope = Self.mergedRefreshScope(
                pendingAutomaticRefreshScope,
                scope
            )
            return
        }
        startScan(scope: scope, background: true)
    }

    private func startPendingAutomaticRefreshIfNeeded() {
        guard !isScanning, !isCleaning,
              let scope = pendingAutomaticRefreshScope else { return }
        pendingAutomaticRefreshScope = nil
        startScan(scope: scope, background: true)
    }

    private static func mergedRefreshScope(
        _ current: ScanScope?,
        _ incoming: ScanScope
    ) -> ScanScope {
        guard let current else { return incoming }
        if current == .full || incoming == .full {
            return .full
        }
        if current == .developerAI || incoming == .developerAI {
            return .developerAI
        }
        return .applications
    }

    private func snapshotAfterCleanup(
        _ snapshot: ScanSnapshot,
        plan: CleanupPlan,
        transaction: CleanupTransaction
    ) -> ScanSnapshot? {
        let movedCandidateIDs = Set(transaction.outcomes.compactMap {
            $0.status == .movedToTrash ? $0.candidateID : nil
        })
        let movedCandidates = plan.candidates.filter {
            movedCandidateIDs.contains($0.id)
        }
        guard !movedCandidates.isEmpty else { return nil }

        let movedRoots = movedCandidates.map {
            $0.url.standardizedFileURL.resolvingSymlinksInPath().path
        }
        func wasMoved(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.resolvingSymlinksInPath().path
            return movedRoots.contains {
                path == $0 || path.hasPrefix($0 + "/")
            }
        }

        let remainingItems = snapshot.items.filter { !wasMoved($0.url) }
        let remainingItemIDs = Set(remainingItems.map(\.id))
        let applications: [ApplicationRecord] = snapshot.applications.compactMap { application in
            guard !wasMoved(application.url) else { return nil }
            return ApplicationRecord(
                id: application.id,
                name: application.name,
                bundleIdentifier: application.bundleIdentifier,
                version: application.version,
                url: application.url,
                executableURL: application.executableURL,
                allocatedSize: application.allocatedSize,
                lastUsedDate: application.lastUsedDate,
                associations: application.associations.filter {
                    remainingItemIDs.contains($0.itemID)
                }
            )
        }
        let aiApplications: [AIApplicationRecord] = snapshot.aiApplications.compactMap { application in
            if let applicationURL = application.applicationURL,
               wasMoved(applicationURL) {
                return nil
            }
            return AIApplicationRecord(
                id: application.id,
                name: application.name,
                bundleIdentifier: application.bundleIdentifier,
                applicationURL: application.applicationURL,
                rootURLs: application.rootURLs.filter { !wasMoved($0) },
                itemIDs: application.itemIDs.intersection(remainingItemIDs),
                pluginIDs: application.pluginIDs,
                skillIDs: application.skillIDs,
                applicationAllocatedSize: application.applicationAllocatedSize,
                supportLevel: application.supportLevel
            )
        }
        let categoryByItemID = Dictionary(
            uniqueKeysWithValues: snapshot.items.map { ($0.id, $0.category) }
        )
        var aggregates = Dictionary(
            uniqueKeysWithValues: (snapshot.categoryAggregates ?? []).map {
                ($0.category, $0)
            }
        )
        for candidate in movedCandidates {
            guard let category = categoryByItemID[candidate.itemID],
                  let aggregate = aggregates[category] else { continue }
            aggregates[category] = CategoryAggregate(
                category: category,
                allocatedSize: max(0, aggregate.allocatedSize - candidate.allocatedSize),
                itemCount: max(0, aggregate.itemCount - 1)
            )
        }
        return ScanSnapshot(
            completedAt: .now,
            volume: (try? VolumeScanner().scan()) ?? snapshot.volume,
            items: remainingItems,
            applications: applications,
            aiApplications: aiApplications,
            plugins: snapshot.plugins,
            skills: snapshot.skills,
            coverage: snapshot.coverage,
            pluginDiagnostics: snapshot.pluginDiagnostics,
            categoryAggregates: aggregates.isEmpty
                ? snapshot.categoryAggregates
                : Array(aggregates.values)
        )
    }

    private func snapshot(
        _ snapshot: ScanSnapshot,
        applying analysis: ApplicationDetailAnalysis
    ) -> ScanSnapshot? {
        guard let target = snapshot.applications.first(where: {
            $0.id == analysis.applicationID
        }) else {
            return nil
        }
        let oldTargetItemIDs = Set(target.associations.map(\.itemID))
        let otherApplicationItemIDs = Set(
            snapshot.applications
                .filter { $0.id != target.id }
                .flatMap(\.associations)
                .map(\.itemID)
        )
        let aiItemIDs = Set(snapshot.aiApplications.flatMap(\.itemIDs))
        let protectedItemIDs = otherApplicationItemIDs.union(aiItemIDs)
        var items = snapshot.items.filter {
            !oldTargetItemIDs.contains($0.id)
                || protectedItemIDs.contains($0.id)
        }
        var itemIndexByPath = Dictionary(
            items.enumerated().map {
                ($0.element.url.standardizedFileURL.path, $0.offset)
            },
            uniquingKeysWith: { first, _ in first }
        )
        var itemIDByAnalysisItemID = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0.id) }
        )

        for item in analysis.items {
            let path = item.url.standardizedFileURL.path
            if let existingIndex = itemIndexByPath[path] {
                let existing = items[existingIndex]
                itemIDByAnalysisItemID[item.id] = existing.id
                if otherApplicationItemIDs.contains(existing.id) {
                    items[existingIndex] = ScannedItem(
                        id: existing.id,
                        url: existing.url,
                        logicalSize: max(
                            existing.logicalSize,
                            item.logicalSize
                        ),
                        allocatedSize: max(
                            existing.allocatedSize,
                            item.allocatedSize
                        ),
                        creationDate: existing.creationDate,
                        modificationDate: item.modificationDate
                            ?? existing.modificationDate,
                        resourceIdentifier: item.resourceIdentifier
                            ?? existing.resourceIdentifier,
                        category: existing.category,
                        risk: max(existing.risk, item.risk),
                        ownerID: nil,
                        explanation: existing.explanation
                    )
                }
                continue
            }
            itemIndexByPath[path] = items.count
            itemIDByAnalysisItemID[item.id] = item.id
            items.append(item)
        }

        let associations = analysis.associations.compactMap {
            association -> ArtifactAssociation? in
            guard let itemID = itemIDByAnalysisItemID[
                association.itemID
            ] else {
                return nil
            }
            let isShared = otherApplicationItemIDs.contains(itemID)
            return ArtifactAssociation(
                itemID: itemID,
                applicationID: target.id,
                evidence: association.evidence,
                confidence: association.confidence,
                risk: association.risk,
                ownership: isShared ? .shared : association.ownership
            )
        }
        let applications = snapshot.applications.map { application in
            guard application.id == target.id else { return application }
            return ApplicationRecord(
                id: application.id,
                name: application.name,
                bundleIdentifier: application.bundleIdentifier,
                version: application.version,
                url: application.url,
                executableURL: application.executableURL,
                allocatedSize: application.allocatedSize,
                lastUsedDate: application.lastUsedDate,
                associations: associations
            )
        }
        return ScanSnapshot(
            completedAt: .now,
            volume: snapshot.volume,
            items: items,
            applications: applications,
            aiApplications: snapshot.aiApplications,
            plugins: snapshot.plugins,
            skills: snapshot.skills,
            coverage: snapshot.coverage,
            pluginDiagnostics: snapshot.pluginDiagnostics,
            categoryAggregates: updatedCategoryAggregates(
                previous: snapshot,
                items: items
            )
        ).compacted()
    }

    private func updatedCategoryAggregates(
        previous snapshot: ScanSnapshot,
        items: [ScannedItem]
    ) -> [CategoryAggregate]? {
        guard let previous = snapshot.categoryAggregates else {
            return nil
        }
        let oldItems = Dictionary(
            uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) }
        )
        let newItems = Dictionary(
            uniqueKeysWithValues: items.map { ($0.id, $0) }
        )
        var aggregates = Dictionary(
            uniqueKeysWithValues: previous.map { ($0.category, $0) }
        )
        for item in oldItems.values where newItems[item.id] == nil {
            let current = aggregates[item.category]
                ?? CategoryAggregate(
                    category: item.category,
                    allocatedSize: 0,
                    itemCount: 0
                )
            aggregates[item.category] = CategoryAggregate(
                category: item.category,
                allocatedSize: max(
                    0,
                    current.allocatedSize - item.allocatedSize
                ),
                itemCount: max(0, current.itemCount - 1)
            )
        }
        for item in newItems.values where oldItems[item.id] == nil {
            let current = aggregates[item.category]
                ?? CategoryAggregate(
                    category: item.category,
                    allocatedSize: 0,
                    itemCount: 0
                )
            aggregates[item.category] = CategoryAggregate(
                category: item.category,
                allocatedSize: current.allocatedSize + item.allocatedSize,
                itemCount: current.itemCount + 1
            )
        }
        return Array(aggregates.values)
    }

    private func apply(snapshot: ScanSnapshot) {
        latestSnapshot = snapshot
        projection = nil
        cancelAIQueryProjection()
        projectionPublicationTask?.cancel()
        projectionWorker?.cancel()

        startAIManagementDiscovery(for: snapshot, force: consumePendingForceAIDiscovery())

        let worker = Task.detached(priority: .userInitiated) { [snapshot] in
            try AppSnapshotProjection.build(snapshot: snapshot)
        }
        projectionWorker = worker
        projectionPublicationTask = Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self,
                      !Task.isCancelled,
                      self.latestSnapshot?.id == result.snapshotID else { return }
                self.projection = result
                self.refreshAIQueryProjection()
            } catch is CancellationError {
                return
            } catch {
                guard let self, self.latestSnapshot?.id == snapshot.id else { return }
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func refreshAIQueryProjection() {
        cancelAIQueryProjection()
        guard selection == .developerAI,
              let projection,
              let selectedAIApplicationID,
              let application = projection.developerAI.applications.first(where: {
                  $0.id == selectedAIApplicationID
              }) else { return }

        let query = searchText
        if query.isEmpty {
            aiQueryProjection = try? AIApplicationQueryProjection.build(
                application: application,
                query: query
            )
            return
        }

        let snapshotID = projection.snapshotID
        let worker = Task.detached(priority: .userInitiated) { [application, query] in
            try AIApplicationQueryProjection.build(application: application, query: query)
        }
        aiQueryWorker = worker
        aiQueryPublicationTask = Task { [weak self] in
            do {
                let result = try await worker.value
                guard let self,
                      !Task.isCancelled,
                      self.projection?.snapshotID == snapshotID,
                      self.selectedAIApplicationID == result.applicationID,
                      self.searchText == result.query else { return }
                self.aiQueryProjection = result
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func cancelAIQueryProjection() {
        aiQueryProjection = nil
        aiQueryPublicationTask?.cancel()
        aiQueryWorker?.cancel()
    }

    // MARK: - AI management discovery

    /// Reads and clears the one-shot "force discovery" request.
    private func consumePendingForceAIDiscovery() -> Bool {
        defer { pendingForceAIDiscovery = false }
        return pendingForceAIDiscovery
    }

    /// Launches read-only AI-tool discovery for a snapshot. The old pass (worker
    /// and its publication task) is always cancelled first. When `force` is false
    /// and the AI-relevant inputs are unchanged from the last launched pass,
    /// discovery is skipped so routine (for example, storage) refreshes don't
    /// re-run CLI probes.
    ///
    /// Work runs on a detached, non-MainActor worker so directory probes and the
    /// definition loop never block the UI; the detached closure captures only
    /// `Sendable` values (snapshot, home, the discover function), never `self`.
    /// Publication stays on the MainActor and is guarded three ways: the task
    /// must not be cancelled, the generation must still be current, and
    /// `latestSnapshot.id` must still match the captured snapshot. That guarantees
    /// a stale pass can never overwrite results from a newer snapshot.
    private func startAIManagementDiscovery(for snapshot: ScanSnapshot, force: Bool) {
        guard let homeDirectory = aiDiscoveryHomeURL else { return }
        let fingerprint = AIDiscoveryFingerprint(snapshot: snapshot)
        if !force,
           isDiscoveringAITools == false,
           lastSuccessfulAIDiscoveryFingerprint == fingerprint {
            // Inputs unchanged since a successful pass and none in flight: keep
            // existing results.
            return
        }

        aiDiscoveryPublicationTask?.cancel()
        aiDiscoveryWorker?.cancel()
        aiDiscoveryGeneration &+= 1
        let generation = aiDiscoveryGeneration
        let snapshotID = snapshot.id
        isDiscoveringAITools = true
        aiDiscoveryError = nil

        let discover = discoverAITools
        let worker = Task.detached(priority: .utility) { [snapshot, homeDirectory, discover] in
            try await discover(snapshot, homeDirectory)
        }
        aiDiscoveryWorker = worker
        aiDiscoveryPublicationTask = Task { [weak self] in
            do {
                let records = try await worker.value
                guard let self,
                      !Task.isCancelled,
                      self.aiDiscoveryGeneration == generation,
                      self.latestSnapshot?.id == snapshotID else { return }
                self.aiManagementProjection = AIManagementProjection(records: records)
                // Record success only now, so a failed/cancelled pass never marks
                // these inputs as covered and a retry stays possible.
                self.lastSuccessfulAIDiscoveryFingerprint = fingerprint
                self.isDiscoveringAITools = false
                self.aiDiscoveryWorker = nil
                self.aiDiscoveryPublicationTask = nil
            } catch is CancellationError {
                // Superseded or cancelled: leave state (including fingerprint) for
                // the newer pass to own; the same inputs may retry later.
                return
            } catch {
                guard let self,
                      self.aiDiscoveryGeneration == generation,
                      self.latestSnapshot?.id == snapshotID else { return }
                // Surface as a discovery-only error; never clobber the main scan
                // error, never clear a still-valid prior projection, and do not
                // mark the fingerprint successful so the same inputs can retry.
                self.aiDiscoveryError = error.localizedDescription
                self.isDiscoveringAITools = false
                self.aiDiscoveryWorker = nil
                self.aiDiscoveryPublicationTask = nil
                Self.logger.error(
                    "AI tool discovery failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Cancels any in-flight discovery and invalidates its generation, so a
    /// worker that is mid-flight can never publish after cancellation.
    private func cancelAIManagementDiscovery() {
        aiDiscoveryPublicationTask?.cancel()
        aiDiscoveryWorker?.cancel()
        aiDiscoveryPublicationTask = nil
        aiDiscoveryWorker = nil
        aiDiscoveryGeneration &+= 1
        isDiscoveringAITools = false
    }

    #if DEBUG
    /// Test-only seam: drives a snapshot through the same `apply(snapshot:)`
    /// entry point production uses, optionally forcing a fresh discovery pass,
    /// then awaits the current discovery pass (worker + publication) so races can
    /// be asserted deterministically. Never used in production.
    func applySnapshotForTesting(_ snapshot: ScanSnapshot, force: Bool = false) async {
        pendingForceAIDiscovery = force
        apply(snapshot: snapshot)
        await aiDiscoveryPublicationTask?.value
    }

    /// Test-only seam: applies a snapshot without awaiting discovery, so a slow
    /// or gated pass can be left in flight while a newer snapshot is applied. It
    /// returns the publication task for the pass it started (if any) so a test
    /// can deterministically await that specific pass finishing.
    @discardableResult
    func startForTesting(_ snapshot: ScanSnapshot, force: Bool = false) -> Task<Void, Never>? {
        pendingForceAIDiscovery = force
        apply(snapshot: snapshot)
        return aiDiscoveryPublicationTask
    }
    #endif

    func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "SpacePilot-Diagnostics.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DiagnosticReport(
                snapshot: latestSnapshot,
                cleanupTransactionCount: cleanupHistory.count
            ).encoded().write(to: url, options: .atomic)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// A structured, stable fingerprint of the AI-relevant inputs of a snapshot: the
/// bundle identifiers and application URLs that feed the snapshot-backed locator.
/// Entries are standardized and sorted, so equality is order-independent and
/// robust to paths containing separators or newlines (no string concatenation).
///
/// Home-directory-relative filesystem presence is deliberately not captured, so
/// an explicit `force` is required to pick up on-disk changes that don't alter
/// the snapshot itself.
private struct AIDiscoveryFingerprint: Equatable, Sendable {
    private struct Entry: Equatable, Sendable, Comparable {
        let kind: String
        let bundleIdentifier: String?
        let path: String?

        static func < (lhs: Entry, rhs: Entry) -> Bool {
            if lhs.kind != rhs.kind { return lhs.kind < rhs.kind }
            if lhs.bundleIdentifier != rhs.bundleIdentifier {
                return (lhs.bundleIdentifier ?? "") < (rhs.bundleIdentifier ?? "")
            }
            return (lhs.path ?? "") < (rhs.path ?? "")
        }
    }

    private let entries: [Entry]

    init(snapshot: ScanSnapshot) {
        var entries: [Entry] = []
        for application in snapshot.aiApplications {
            entries.append(Entry(
                kind: "ai",
                bundleIdentifier: application.bundleIdentifier,
                path: application.applicationURL?.standardizedFileURL.path
            ))
        }
        for application in snapshot.applications {
            guard let bundle = application.bundleIdentifier else { continue }
            entries.append(Entry(
                kind: "app",
                bundleIdentifier: bundle,
                path: application.url.standardizedFileURL.path
            ))
        }
        self.entries = entries.sorted()
    }
}
