import AppKit
import Foundation
import Observation
import SpacePilotCore

@MainActor
@Observable
final class AppModel {
    var selection: NavigationDestination? = .overview
    var searchText = ""
    var selectedAIApplicationID: UUID?
    var selectedAIApplicationTab: AIApplicationTab = .overview
    var latestSnapshot: ScanSnapshot?
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
                    if let snapshot = event.snapshot { latestSnapshot = snapshot }
                }
            } catch is CancellationError {
                scanMessage = "Scan cancelled"
            } catch {
                errorMessage = error.localizedDescription
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
                showingCleanupConfirmation = false
                startScan()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCleaning = false
            cleanupTask = nil
        }
    }

    private func loadSavedState() async {
        guard let runtime else { return }
        do {
            latestSnapshot = try await runtime.store.latestSnapshot()
            cleanupHistory = try await runtime.store.cleanupHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
