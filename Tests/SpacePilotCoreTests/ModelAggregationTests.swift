import Foundation
import XCTest
@testable import SpacePilotCore

final class ModelAggregationTests: XCTestCase {
    func testSharedSkillIsNotDoubleCountedAcrossAIApplications() {
        let sharedID = UUID()
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            skillIDs: [sharedID],
            applicationAllocatedSize: 100
        )
        let claude = AIApplicationRecord.fixture(
            name: "Claude",
            skillIDs: [sharedID],
            applicationAllocatedSize: 200
        )
        let skill = SkillRecord.fixture(
            id: sharedID,
            allocatedSize: 50,
            scope: .sharedAgents
        )
        let snapshot = ScanSnapshot.fixture(
            aiApplications: [codex, claude],
            skills: [skill]
        )

        XCTAssertEqual(snapshot.uniqueAIAllocatedSize, 350)
    }

    func testRiskSortPlacesSensitiveAndManagedLast() {
        XCTAssertEqual(RiskLevel.allCases.sorted().map(\.rawValue), [
            "safe", "rebuildable", "sensitive", "managed"
        ])
    }

    func testByteCountUsesFileStyleFormatting() {
        let output = ByteCount.string(1_024)
        XCTAssertTrue(output.contains("1"))
        XCTAssertTrue(output.localizedCaseInsensitiveContains("KB"))
    }
}
