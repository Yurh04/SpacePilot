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
    var isCleaning = false
    var showingCleanupConfirmation = false
    var cleanupCandidates: [CleanupReviewItem] = []
    var latestCleanupTransaction: CleanupTransaction?
    var cleanupHistory: [CleanupTransaction] = []

    var isPreparingAIQuery: Bool {
        guard selection == .developerAI,
              !searchText.isEmpty,
              let selectedAIApplicationID else { return false }
        return aiQueryProjection?.applicationID != selectedAIApplicationID
            || aiQueryProjection?.query != searchText
    }

    var canRefreshCurrentView: Bool {
        selection != .history
    }

    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var cleanupOperationID: UUID?
    private var projectionWorker: Task<AppSnapshotProjection, Error>?
    private var projectionPublicationTask: Task<Void, Never>?
    private var aiQueryWorker: Task<AIApplicationQueryProjection, Error>?
    private var aiQueryPublicationTask: Task<Void, Never>?
    private let runtime: SpacePilotRuntime?

    init() {
        do {
            runtime = try .live()
        } catch {
            runtime = nil
            errorMessage = error.localizedDescription
        }
        Task { await loadSavedState() }
    }

    func startScan(scope: ScanScope = .applications) {
        guard !isScanning, let coordinator = runtime?.coordinator else { return }
        errorMessage = nil
        isScanning = true
        scanTask = Task {
            do {
                for try await event in coordinator.scan(scope: scope) {
                    guard !Task.isCancelled else { break }
                    scanStage = event.stage
                    scanProgress = event.progress
                    scanMessage = event.message
                    if let snapshot = event.snapshot { apply(snapshot: snapshot) }
                    Self.logger.info("Scan stage: \(event.stage.rawValue, privacy: .public)")
                }
            } catch is CancellationError {
                scanMessage = L10n.text(.scanCancelled)
            } catch {
                errorMessage = error.localizedDescription
                Self.logger.error("Scan failed: \(error.localizedDescription, privacy: .public)")
            }
            isScanning = false
            scanTask = nil
        }
    }

    func cancelScan() {
        scanTask?.cancel()
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

    private func apply(snapshot: ScanSnapshot) {
        latestSnapshot = snapshot
        projection = nil
        cancelAIQueryProjection()
        projectionPublicationTask?.cancel()
        projectionWorker?.cancel()

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
