import Foundation
@testable import SpacePilotCore

actor InMemorySnapshotStore: SnapshotStoring {
    private(set) var latest: ScanSnapshot?
    private(set) var saveCount = 0
    private var history: [CleanupTransaction] = []

    init(latest: ScanSnapshot? = nil) {
        self.latest = latest
    }

    func save(snapshot: ScanSnapshot) async throws {
        latest = snapshot
        saveCount += 1
    }

    func latestSnapshot() async throws -> ScanSnapshot? { latest }

    func save(transaction: CleanupTransaction) async throws {
        history.append(transaction)
    }

    func cleanupHistory() async throws -> [CleanupTransaction] { history }
}

struct FixedDirectoryStatProvider: DirectoryStatProviding {
    let values: [String: DirectoryStat]

    init(_ values: [URL: (logical: Int64, allocated: Int64)]) {
        self.values = Dictionary(
            uniqueKeysWithValues: values.map { url, sizes in
                (
                    url.standardizedFileURL.path,
                    DirectoryStat(
                        resourceID: url.standardizedFileURL.path,
                        totalLogicalSize: sizes.logical,
                        totalAllocatedSize: sizes.allocated,
                        indexedAt: .now
                    )
                )
            }
        )
    }

    func cachedDirectoryStat(at url: URL) async throws -> DirectoryStat? {
        values[url.standardizedFileURL.path]
    }
}

extension ScanCoordinator {
    static func fixture(
        store: InMemorySnapshotStore = InMemorySnapshotStore(),
        suspendDuring: ScanStage? = nil
    ) -> ScanCoordinator {
        ScanCoordinator(operation: { emit in
            emit(ScanEvent(stage: .quickInventory, progress: 0.2, message: "Quick inventory"))
            if suspendDuring == .targetedAnalysis {
                try await Task.sleep(for: .seconds(30))
            }
            try Task.checkCancellation()
            emit(ScanEvent(stage: .targetedAnalysis, progress: 0.7, message: "Targeted analysis"))
            let snapshot = ScanSnapshot.fixture()
            try await store.save(snapshot: snapshot)
            emit(ScanEvent(stage: .completed, progress: 1, message: "Completed", snapshot: snapshot))
            return snapshot
        })
    }
}
