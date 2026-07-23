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
        XCTAssertEqual(result.outcomes.first?.reason, .changedIdentity)
        XCTAssertEqual(result.outcomes.first?.sourceURL, file)
        XCTAssertEqual(result.outcomes.first?.sourceExplanation, "Test cache")
        XCTAssertTrue(mover.movedURLs.isEmpty)
    }

    func testMissingSourceIsDistinguishedFromChangedIdentity() async throws {
        let tree = try TemporaryTree(files: [:])
        let file = tree.url.appending(path: "Library/Caches/app/missing.bin")
        let mover = RecordingTrashMover()
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: mover
        )
        let plan = CleanupPlan(snapshotID: UUID(), candidates: [candidate(for: file)])

        let result = try await executor.execute(plan: plan)

        XCTAssertEqual(result.outcomes.first?.status, .skippedChanged)
        XCTAssertEqual(result.outcomes.first?.reason, .missingSource)
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
        XCTAssertEqual(result.outcomes.map(\.reason), [.moved, .moveFailed])
    }

    func testPermissionFailureHasSpecificReason() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/app/file": 8])
        let file = tree.url.appending(path: "Library/Caches/app/file")
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: FailingTrashMover(error: CocoaError(.fileWriteNoPermission))
        )

        let result = try await executor.execute(
            plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate(for: file)])
        )

        XCTAssertEqual(result.outcomes.first?.status, .failed)
        XCTAssertEqual(result.outcomes.first?.reason, .permissionDenied)
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
        XCTAssertEqual(result.outcomes.first?.reason, .protectedPath)
        XCTAssertTrue(mover.movedURLs.isEmpty)
    }

    func testVerifiedBytesCountOnlySourcesThatActuallyMoved() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/app/cache.bin": 32])
        let file = tree.url.appending(path: "Library/Caches/app/cache.bin")
        let candidate = candidate(for: file)
        let mover = try FixtureTrashMover(destination: tree.url.appending(path: "FixtureTrash"))
        let executor = CleanupExecutor(
            policy: PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url),
            mover: mover
        )

        let transaction = try await executor.execute(
            plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate])
        )

        XCTAssertEqual(transaction.verifiedFreedBytes, candidate.allocatedSize)
        XCTAssertEqual(transaction.outcomes.first?.reason, .moved)
        XCTAssertEqual(transaction.outcomes.first?.sourceAllocatedSize, candidate.allocatedSize)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testDirectoryWithChangedContentsStillMovesWhenRootIdentityMatches() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
        let directory = tree.url.appending(path: "Library/Caches/live")
        let policy = PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url)
        let item = ScannedItem(
            url: directory,
            logicalSize: 16,
            allocatedSize: 16,
            category: .cache,
            risk: .safe,
            explanation: "Live cache"
        )
        let candidate = try CleanupCandidateRefresher().refresh(item: item, policy: policy)
        try Data(repeating: 2, count: 512).write(to: directory.appending(path: "new.bin"))
        let mover = try FixtureTrashMover(destination: tree.url.appending(path: "FixtureTrash"))

        let result = try await CleanupExecutor(policy: policy, mover: mover)
            .execute(plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate]))

        XCTAssertEqual(result.outcomes.first?.status, .movedToTrash)
    }

    func testReplacedDirectoryIsSkipped() async throws {
        let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
        let directory = tree.url.appending(path: "Library/Caches/live")
        let policy = PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url)
        let item = ScannedItem(
            url: directory,
            logicalSize: 16,
            allocatedSize: 16,
            category: .cache,
            risk: .safe,
            explanation: "Live cache"
        )
        let candidate = try CleanupCandidateRefresher().refresh(item: item, policy: policy)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let result = try await CleanupExecutor(policy: policy, mover: RecordingTrashMover())
            .execute(plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate]))

        XCTAssertEqual(result.outcomes.first?.status, .skippedChanged)
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

private struct FailingTrashMover: TrashMoving {
    let error: CocoaError

    func moveToTrash(_ url: URL) throws -> URL {
        throw error
    }
}
