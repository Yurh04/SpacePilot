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

    func testSafeItemBecomesCandidateWithIdentityMetadata() throws {
        let date = Date(timeIntervalSince1970: 123)
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/app/file",
            risk: .safe,
            allocatedSize: 512,
            modificationDate: date,
            resourceIdentifier: "resource-1"
        )

        let plan = try CleanupPlanner(policy: policy).makePlan(
            snapshotID: UUID(),
            items: [item],
            selectedIDs: [item.id],
            separatelyConfirmedSensitiveIDs: []
        )

        XCTAssertEqual(plan.candidates.first?.expectedModificationDate, date)
        XCTAssertEqual(plan.candidates.first?.expectedResourceIdentifier, "resource-1")
        XCTAssertEqual(plan.candidates.first?.allocatedSize, 512)
    }
}
