import Foundation
import Observation
import SpacePilotCore

@MainActor
@Observable
final class AppModel {
    var selection: NavigationDestination? = .overview
    var latestSnapshot: ScanSnapshot?
    var scanStage: ScanStage?
    var scanProgress = 0.0
    var scanMessage = "Ready to scan"
    var errorMessage: String?
    var isScanning = false

    private var scanTask: Task<Void, Never>?
    private let coordinator: ScanCoordinator?

    init() {
        do {
            coordinator = try .live()
        } catch {
            coordinator = nil
            errorMessage = error.localizedDescription
        }
    }

    func startScan() {
        guard !isScanning, let coordinator else { return }
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
}
