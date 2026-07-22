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
    var selection: NavigationDestination? = .overview
    var searchText = ""
    var selectedAIApplicationID: UUID?
    var selectedAIApplicationTab: AIApplicationTab = .overview
    var latestSnapshot: ScanSnapshot?
    var projection: AppSnapshotProjection?
    var scanStage: ScanStage?
    var scanProgress = 0.0
    var scanMessage = "Ready to scan"
    var errorMessage: String?
    var isScanning = false
    var isCleaning = false
    var showingCleanupConfirmation = false
    var cleanupCandidates: [ScannedItem] = []
    var latestCleanupTransaction: CleanupTransaction?
    var cleanupHistory: [CleanupTransaction] = []

    private var scanTask: Task<Void, Never>?
    private var cleanupTask: Task<Void, Never>?
    private var projectionTask: Task<Void, Never>?
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

    func startScan() {
        guard !isScanning, let coordinator = runtime?.coordinator else { return }
        errorMessage = nil
        isScanning = true
        scanTask = Task {
            do {
                for try await event in coordinator.scan() {
                    guard !Task.isCancelled else { break }
                    scanStage = event.stage
                    scanProgress = event.progress
                    scanMessage = event.message
                    if let snapshot = event.snapshot { apply(snapshot: snapshot) }
                    Self.logger.info("Scan stage: \(event.stage.rawValue, privacy: .public)")
                }
            } catch is CancellationError {
                scanMessage = "Scan cancelled"
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

    func prepareCleanup(items: [ScannedItem]) {
        let eligible = items.filter { $0.risk != .managed }
        guard !eligible.isEmpty else { return }
        cleanupCandidates = eligible
        latestCleanupTransaction = nil
        showingCleanupConfirmation = true
    }

    func prepareUninstall(application: ApplicationRecord) {
        guard let snapshot = latestSnapshot else { return }
        if let bundleID = application.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            errorMessage = "Quit \(application.name) before uninstalling it."
            return
        }
        prepareCleanup(items: ApplicationUninstallPlanner().cleanupItems(for: application, snapshot: snapshot))
    }

    func prepareReset(application: ApplicationRecord) {
        guard let snapshot = latestSnapshot else { return }
        let items = ApplicationUninstallPlanner().resetItems(for: application, snapshot: snapshot)
        guard !items.isEmpty else {
            errorMessage = "No high-confidence settings or caches are available to reset for \(application.name)."
            return
        }
        prepareCleanup(items: items)
    }

    func executePreparedCleanup(confirmSensitive: Bool) {
        guard let runtime, let snapshot = latestSnapshot, !isCleaning else { return }
        isCleaning = true
        errorMessage = nil
        cleanupTask = Task {
            do {
                let sensitiveIDs = confirmSensitive
                    ? Set(cleanupCandidates.filter { $0.risk == .sensitive }.map(\.id))
                    : []
                let policy = PathSafetyPolicy(
                    homeDirectory: runtime.homeDirectory,
                    allowedVolumeRoot: URL(fileURLWithPath: "/", isDirectory: true)
                )
                let plan = try CleanupPlanner(policy: policy).makePlan(
                    snapshotID: snapshot.id,
                    items: cleanupCandidates,
                    selectedIDs: Set(cleanupCandidates.map(\.id)),
                    separatelyConfirmedSensitiveIDs: sensitiveIDs
                )
                let transaction = try await CleanupExecutor(
                    policy: policy,
                    mover: FileManagerTrashMover(),
                    store: runtime.store
                ).execute(plan: plan)
                latestCleanupTransaction = transaction
                cleanupHistory = try await runtime.store.cleanupHistory()
                Self.logger.info("Cleanup finished: \(transaction.summary.rawValue, privacy: .public)")
                showingCleanupConfirmation = false
                startScan()
            } catch {
                errorMessage = error.localizedDescription
                Self.logger.error("Cleanup failed: \(error.localizedDescription, privacy: .public)")
            }
            isCleaning = false
            cleanupTask = nil
        }
    }

    private func loadSavedState() async {
        guard let runtime else { return }
        do {
            if let snapshot = try await runtime.store.latestSnapshot() {
                apply(snapshot: snapshot)
            }
            cleanupHistory = try await runtime.store.cleanupHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(snapshot: ScanSnapshot) {
        latestSnapshot = snapshot
        projection = nil
        projectionTask?.cancel()
        projectionTask = Task {
            let result = await Task.detached(priority: .userInitiated) {
                AppSnapshotProjection(snapshot: snapshot)
            }.value
            guard !Task.isCancelled, latestSnapshot?.id == result.snapshotID else { return }
            projection = result
        }
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
