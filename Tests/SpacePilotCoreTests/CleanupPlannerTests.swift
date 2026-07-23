import Foundation
import XCTest
@testable import SpacePilotCore

final class CleanupPlannerTests: XCTestCase {
    private let policy = PathSafetyPolicy(
        homeDirectory: URL(fileURLWithPath: "/Users/test"),
        allowedVolumeRoot: URL(fileURLWithPath: "/")
    )

    func testSensitiveItemRequiresSeparateConfirmation() {
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/AI/conversation.json",
            risk: .sensitive
        )

        XCTAssertThrowsError(try CleanupPlanner(policy: policy).makePlan(
            snapshotID: UUID(),
            items: [item],
            selectedIDs: [item.id],
            separatelyConfirmedSensitiveIDs: []
        ))
    }

    func testManagedItemCannotEnterPlan() {
        let item = ScannedItem.fixture(
            path: "/Users/test/.codex/plugins/cache/managed-skill",
            risk: .managed
        )

        XCTAssertThrowsError(try CleanupPlanner(policy: policy).makePlan(
            snapshotID: UUID(),
            items: [item],
            selectedIDs: [item.id],
            separatelyConfirmedSensitiveIDs: [item.id]
        ))
    }

    func testPlannerRefreshesStaleDirectoryMetadata() throws {
        let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
        let directory = tree.url.appending(path: "Library/Caches/live")
        let stale = ScannedItem(
            url: directory,
            logicalSize: 1,
            allocatedSize: 1,
            category: .cache,
            risk: .safe,
            explanation: "Live cache"
        )
        try Data(repeating: 1, count: 4_096).write(to: directory.appending(path: "new.bin"))

        let plan = try CleanupPlanner(policy: .init(
            homeDirectory: tree.url,
            allowedVolumeRoot: tree.url
        )).makePlan(
            snapshotID: UUID(),
            items: [stale],
            selectedIDs: [stale.id],
            separatelyConfirmedSensitiveIDs: []
        )

        XCTAssertEqual(plan.candidates.first?.itemKind, .directory)
        XCTAssertGreaterThan(plan.candidates.first?.allocatedSize ?? 0, stale.allocatedSize)
    }

    func testPlannerCapturesRegularFileIdentity() throws {
        let tree = try TemporaryTree(files: ["Library/Caches/live.bin": 16])
        let file = tree.url.appending(path: "Library/Caches/live.bin")
        let stale = ScannedItem(
            url: file,
            logicalSize: 1,
            allocatedSize: 1,
            category: .cache,
            risk: .safe,
            explanation: "Live cache file"
        )

        let plan = try CleanupPlanner(policy: .init(
            homeDirectory: tree.url,
            allowedVolumeRoot: tree.url
        )).makePlan(
            snapshotID: UUID(),
            items: [stale],
            selectedIDs: [stale.id],
            separatelyConfirmedSensitiveIDs: []
        )

        XCTAssertEqual(plan.candidates.first?.itemKind, .regularFile)
        XCTAssertGreaterThan(plan.candidates.first?.allocatedSize ?? 0, stale.allocatedSize)
    }
}
