import XCTest
@testable import SpacePilotCore

final class SkillDuplicationAnalyzerTests: XCTestCase {
    private func skill(
        _ name: String,
        path: String,
        fingerprint: String,
        size: Int64 = 1_000
    ) -> SkillRecord {
        SkillRecord(
            name: name, summary: "", url: URL(fileURLWithPath: path),
            allocatedSize: size, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: fingerprint, conflict: nil,
            managementStatus: .standalone, owner: .shared, locationScope: .userGlobal
        )
    }

    /// The core promise: an entity stored twice is reported once, with the size
    /// of the redundant copy — not the size of both.
    func testTwoPhysicalCopiesReportOneGroupAndOneUnitReclaimable() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("bytedcli", path: "/Users/x/.agents/skills/bytedcli", fingerprint: "aaa"),
            skill("bytedcli", path: "/Users/x/.cc-switch/skills/bytedcli", fingerprint: "aaa")
        ])
        XCTAssertEqual(result.duplicatedEntityCount, 1)
        let group = try! XCTUnwrap(result.groups.first)
        XCTAssertEqual(group.copyCount, 2)
        // Reclaimable is one unit, never the sum of both copies.
        XCTAssertEqual(group.reclaimableSize, 1_000)
        XCTAssertEqual(result.totalReclaimable, 1_000)
    }

    /// Same name but different content is NOT a duplicate. This is the case that
    /// really exists on this machine (`archify`), and reporting it as reclaimable
    /// would tell the user to delete unique content.
    func testSameNameDifferentContentIsNotReportedAsDuplicate() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("archify", path: "/Users/x/.agents/skills/archify", fingerprint: "aaa"),
            skill("archify", path: "/Users/x/.cc-switch/skills/archify", fingerprint: "bbb")
        ])
        XCTAssertTrue(result.groups.isEmpty)
        XCTAssertEqual(result.totalReclaimable, 0)
    }

    /// Three copies must reclaim two units, not three: one copy is always kept.
    func testThreeCopiesReclaimTwoUnits() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("s", path: "/a/s", fingerprint: "f", size: 500),
            skill("s", path: "/b/s", fingerprint: "f", size: 500),
            skill("s", path: "/c/s", fingerprint: "f", size: 500)
        ])
        XCTAssertEqual(result.groups.first?.copyCount, 3)
        XCTAssertEqual(result.totalReclaimable, 1_000)
    }

    /// Records with no fingerprint cannot be proven identical, so they must be
    /// excluded rather than grouped together by accident.
    func testUnfingerprintedSkillsAreNeverGrouped() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("a", path: "/a/x", fingerprint: ""),
            skill("b", path: "/b/x", fingerprint: "")
        ])
        XCTAssertTrue(result.groups.isEmpty)
    }

    /// Groups are ordered by how much space they would free, so the most useful
    /// row is first.
    func testGroupsAreOrderedByReclaimableSizeDescending() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("small", path: "/a/small", fingerprint: "s", size: 10),
            skill("small", path: "/b/small", fingerprint: "s", size: 10),
            skill("big", path: "/a/big", fingerprint: "b", size: 9_000),
            skill("big", path: "/b/big", fingerprint: "b", size: 9_000)
        ])
        XCTAssertEqual(result.groups.map(\.name), ["big", "small"])
    }

    /// A single copy is not a duplicate.
    func testSingleCopyProducesNoGroup() {
        let result = SkillDuplicationAnalyzer.analyze(skills: [
            skill("only", path: "/a/only", fingerprint: "f")
        ])
        XCTAssertTrue(result.groups.isEmpty)
    }
}
