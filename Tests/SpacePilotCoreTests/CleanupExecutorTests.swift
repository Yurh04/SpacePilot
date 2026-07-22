import XCTest
@testable import SpacePilotCore

final class CleanupExecutorTests: XCTestCase {
    func testChangedFileIsSkippedBeforeTrashMove() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/app/cache.bin": 32])
        let file = tree.url.appending(path: "Library/Caches/app/cache.bin")
        let mover = RecordingTrashMover()
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: mover
        )
        let plan = CleanupPlan(
            snapshotID: UUID(),
            candidates: [candidate(for: file, expectedModificationDate: .distantPast)]
        )

        let result = try await executor.execute(plan: plan)

        XCTAssertEqual(result.outcomes.first?.status, .skippedChanged)
        XCTAssertTrue(mover.movedURLs.isEmpty)
    }

    func testFailureIsNotReportedAsTotalSuccess() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Caches/app/one.bin": 16,
            "Library/Caches/app/two.bin": 16
        ])
        let urls = ["one.bin", "two.bin"].map { tree.url.appending(path: "Library/Caches/app/\($0)") }
        let mover = RecordingTrashMover(failingAtIndex: 1)
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: mover
        )
        let plan = CleanupPlan(snapshotID: UUID(), candidates: urls.map { candidate(for: $0) })

        let result = try await executor.execute(plan: plan)

        XCTAssertEqual(result.summary, .partialFailure)
        XCTAssertEqual(result.outcomes.map(\.status), [.movedToTrash, .failed])
    }

    func testProtectedPathIsSkippedEvenIfItAppearsInPlan() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/app/file": 8])
        let mover = RecordingTrashMover()
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: mover
        )
        let candidate = CleanupCandidate(
            itemID: UUID(),
            url: tree.url,
            allocatedSize: 0,
            risk: .safe,
            expectedResourceIdentifier: nil,
            expectedModificationDate: nil,
            explanation: "Invalid broad path"
        )

        let result = try await executor.execute(plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate]))

        XCTAssertEqual(result.outcomes.first?.status, .skippedProtected)
        XCTAssertTrue(mover.movedURLs.isEmpty)
    }

    private func candidate(for url: URL, expectedModificationDate: Date? = nil) -> CleanupCandidate {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey])
        return CleanupCandidate(
            itemID: UUID(),
            url: url,
            allocatedSize: Int64(values?.totalFileAllocatedSize ?? 0),
            risk: .safe,
            expectedResourceIdentifier: values?.fileResourceIdentifier.map { String(describing: $0) },
            expectedModificationDate: expectedModificationDate ?? values?.contentModificationDate,
            explanation: "Test cache"
        )
    }
}
