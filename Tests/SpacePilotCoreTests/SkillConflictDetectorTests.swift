import XCTest
@testable import SpacePilotCore

final class SkillConflictDetectorTests: XCTestCase {
    func testIdenticalSkillsAreMarkedAsExactDuplicates() async throws {
        let roots = try SkillFixtureRoots.make(
            shared: ["review": "Same body"],
            codex: ["review": "Same body"]
        )
        let records = try await SkillScanner().scan(roots: roots.skillRoots)

        let indexed = SkillConflictDetector().detect(in: records)

        XCTAssertTrue(indexed.allSatisfy { $0.conflict == .exactDuplicate })
    }

    func testDifferentSameNameSkillsProduceAgentOverrideWarning() async throws {
        let roots = try SkillFixtureRoots.make(
            shared: ["review": "Shared behavior"],
            codex: ["review": "Codex-specific behavior"]
        )
        let records = try await SkillScanner().scan(roots: roots.skillRoots)

        let indexed = SkillConflictDetector().detect(in: records)

        XCTAssertEqual(indexed.first { $0.scope == .agentSpecific(agent: "Codex") }?.conflict, .agentOverride)
        XCTAssertEqual(indexed.first { $0.scope == .sharedAgents }?.conflict, .sameNameDifferentContent)
    }
}
