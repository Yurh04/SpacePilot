import XCTest
@testable import SpacePilotCore

final class ScanCoordinatorTests: XCTestCase {
    func testQuickInventoryArrivesBeforeTargetedCompletion() async throws {
        let coordinator = ScanCoordinator.fixture()
        var stages: [ScanStage] = []

        for try await event in coordinator.scan() {
            stages.append(event.stage)
        }

        XCTAssertEqual(stages.first, .quickInventory)
        XCTAssertEqual(stages.last, .completed)
    }

    func testCancelledScanDoesNotReplaceLatestSnapshot() async throws {
        let previous = ScanSnapshot.fixture()
        let store = InMemorySnapshotStore(latest: previous)
        let coordinator = ScanCoordinator.fixture(store: store, suspendDuring: .targetedAnalysis)
        let task = Task { try await coordinator.collectScan() }
        try await Task.sleep(for: .milliseconds(20))

        task.cancel()
        _ = try? await task.value

        let saveCount = await store.saveCount
        let latestID = await store.latest?.id
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(latestID, previous.id)
    }

    func testPermissionStatusNeverClaimsFullWhenPathsWereDenied() {
        let denied = [URL(fileURLWithPath: "/Users/test/Library/Mail")]
        XCTAssertEqual(PermissionService().coverageStatus(deniedPaths: denied), .limited(deniedPaths: denied))
    }
}
