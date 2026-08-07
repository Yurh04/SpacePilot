import Foundation
import XCTest
@testable import SpacePilotCore

final class AIManagementProjectionTests: XCTestCase {
    func testEmptyProjection() {
        let projection = AIManagementProjection.empty
        XCTAssertTrue(projection.isEmpty)
        XCTAssertTrue(projection.records.isEmpty)
        XCTAssertTrue(projection.coverageFailureCounts.isEmpty)
    }

    func testGroupsRecordsByKind() {
        let projection = AIManagementProjection(records: [
            record(kind: .plugin, name: "Codex", ownerID: "codex"),
            record(kind: .application, name: "Codex", ownerID: "codex"),
            record(kind: .cli, name: "Codex", ownerID: "codex"),
            record(kind: .skill, name: "Codex", ownerID: "codex")
        ])
        XCTAssertEqual(projection.applications.count, 1)
        XCTAssertEqual(projection.clis.count, 1)
        XCTAssertEqual(projection.skills.count, 1)
        XCTAssertEqual(projection.plugins.count, 1)
    }

    func testDeterministicOrderingIsIndependentOfInput() {
        let a = record(kind: .application, name: "Zed", ownerID: "zed")
        let b = record(kind: .application, name: "Aider", ownerID: "aider")
        let c = record(kind: .cli, name: "Aider", ownerID: "aider")
        let forward = AIManagementProjection(records: [a, b, c])
        let reverse = AIManagementProjection(records: [c, b, a])
        XCTAssertEqual(forward.records, reverse.records)
        // application before cli; within application, Aider before Zed.
        XCTAssertEqual(
            forward.records.map(\.displayName),
            ["Aider", "Zed", "Aider"]
        )
        XCTAssertEqual(
            forward.records.map(\.kind),
            [.application, .application, .cli]
        )
    }

    func testSeparatesToolOwnedAndSharedRecords() {
        let owned = record(kind: .skill, name: "Codex", ownerID: "codex")
        let shared = AIToolRecord(
            id: "skill:shared:/root",
            kind: .skill,
            displayName: "Shared Agent Skills",
            owner: .shared
        )
        let projection = AIManagementProjection(records: [owned, shared])
        XCTAssertEqual(projection.toolOwnedRecords.map(\.id), [owned.id])
        XCTAssertEqual(projection.sharedRecords.map(\.id), [shared.id])
    }

    func testAggregatesCoverageFailures() {
        let projection = AIManagementProjection(records: [
            record(kind: .cli, name: "A", ownerID: "a", failures: [.timeout]),
            record(kind: .cli, name: "B", ownerID: "b", failures: [.timeout, .permissionDenied]),
            record(kind: .application, name: "C", ownerID: "c")
        ])
        XCTAssertEqual(projection.coverageFailureCounts[.timeout], 2)
        XCTAssertEqual(projection.coverageFailureCounts[.permissionDenied], 1)
        XCTAssertNil(projection.coverageFailureCounts[.invalidOutput])
        XCTAssertEqual(projection.recordsWithCoverageFailures.count, 2)
    }

    // MARK: - Fixtures

    private func record(
        kind: AIToolKind,
        name: String,
        ownerID: String,
        failures: Set<AIToolCoverageFailure> = []
    ) -> AIToolRecord {
        let owner = AIToolOwner.tool(definitionID: ownerID)
        return AIToolRecord(
            id: AIToolRecord.stableID(
                kind: kind,
                owner: owner,
                canonicalLocation: "/\(ownerID)/\(kind.rawValue)"
            ),
            kind: kind,
            displayName: name,
            owner: owner,
            coverageFailures: failures
        )
    }
}
