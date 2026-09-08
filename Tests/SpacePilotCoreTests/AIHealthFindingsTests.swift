import XCTest
@testable import SpacePilotCore

final class AIHealthFindingsTests: XCTestCase {

    private func hook(owner: String, event: String, handlers: Int, providers: [String]) -> HookRecord {
        HookRecord(
            event: event,
            ownerDefinitionID: owner,
            sourceURL: URL(fileURLWithPath: "/Users/test/.\(owner)/hooks.json"),
            handlerCount: handlers,
            providers: providers
        )
    }

    private func skill(name: String, fingerprint: String, path: String, size: Int64) -> SkillRecord {
        SkillRecord(
            name: name, summary: "", url: URL(fileURLWithPath: path),
            allocatedSize: size, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: fingerprint, conflict: nil,
            managementStatus: .standalone
        )
    }

    func testDuplicateStorageFindingSummarisesReclaimable() {
        // Same content in two physical locations -> one duplicated entity.
        let dup = SkillDuplicationAnalyzer.analyze(skills: [
            skill(name: "s", fingerprint: "fp", path: "/a/skills/s", size: 100),
            skill(name: "s", fingerprint: "fp", path: "/b/skills/s", size: 100)
        ])
        let findings = AIHealthFindings.analyze(duplication: dup, sizesByPath: [:], hooks: [])
        let dupFinding = findings.first { $0.kind == .duplicateStorage }
        XCTAssertNotNil(dupFinding)
        XCTAssertEqual(dupFinding?.byteCount, 100) // one redundant copy
        XCTAssertEqual(dupFinding?.subject, "1")
    }

    func testLargeFootprintFlagsOverThresholdLargestFirstAndCaps() {
        let big = AIHealthFindings.largeFootprintThreshold
        let sizes: [String: Int64] = [
            "/Users/test/.aiden/checkpoints": big * 3,
            "/Users/test/.codex/logs": big + 1,
            "/Users/test/.claude/cache": big * 2,
            "/Users/test/.opencode": big / 2,          // below threshold, excluded
            "/Users/test/.gemini": big * 5
        ]
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: sizes,
            hooks: []
        )
        let large = findings.filter { $0.kind == .largeFootprint }
        // Capped at maxLargeFootprints, ordered largest first.
        XCTAssertEqual(large.count, AIHealthFindings.maxLargeFootprints)
        XCTAssertEqual(large.map(\.byteCount), [big * 5, big * 3, big * 2])
        XCTAssertEqual(large.first?.subject, ".gemini")
        XCTAssertFalse(large.contains { $0.detail == "/Users/test/.opencode" })
    }

    func testHookTakeoverOnlyWhenSingleExternalProvider() {
        let hooks = [
            // Single external provider + handlers -> takeover.
            hook(owner: "cursor", event: "sessionStart", handlers: 1, providers: ["Flux Island"]),
            // No provider attributed -> not a takeover.
            hook(owner: "codex", event: "PreToolUse", handlers: 3, providers: []),
            // Two providers -> ambiguous, not flagged.
            hook(owner: "codex", event: "Stop", handlers: 2, providers: ["A", "B"])
        ]
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: [:],
            hooks: hooks
        )
        let takeovers = findings.filter { $0.kind == .hookTakeover }
        XCTAssertEqual(takeovers.count, 1)
        XCTAssertEqual(takeovers.first?.subject, "Flux Island")
        XCTAssertEqual(takeovers.first?.detail, "cursor · sessionStart")
    }

    func testEmptyInputsYieldNoFindings() {
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: [:],
            hooks: []
        )
        XCTAssertTrue(findings.isEmpty)
    }

    func testSymlinkDependencySplitsBrokenAndLive() {
        func linked(_ name: String, broken: Bool) -> SkillRecord {
            SkillRecord(
                name: name, summary: "", url: URL(fileURLWithPath: "/a/skills/\(name)"),
                allocatedSize: 0, scope: .sharedAgents, visibleAgents: [],
                parentPluginID: nil, fingerprint: "fp-\(name)", conflict: nil,
                managementStatus: .standalone,
                symlinkTarget: URL(fileURLWithPath: "/store/\(name)"),
                isSymlinkBroken: broken
            )
        }
        let real = skill(name: "real", fingerprint: "r", path: "/a/skills/real", size: 1)
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: [:],
            hooks: [],
            skills: [linked("x", broken: true), linked("y", broken: false), linked("z", broken: false), real]
        )
        let symlink = findings.filter { $0.kind == .symlinkDependency }
        XCTAssertEqual(symlink.count, 2)
        XCTAssertEqual(symlink.first { $0.severity == .warning }?.subject, "1")
        XCTAssertEqual(symlink.first { $0.severity == .info }?.subject, "2")
    }

    func testUnreferencedSkillFlagsRealCopyWhenContentReachedViaSymlink() {
        // A real skill in ~/.agents/skills that nothing links to, whose identical
        // content is ALSO present at ~/.cc-switch/skills which a symlink points at.
        let realCopy = SkillRecord(
            name: "s", summary: "", url: URL(fileURLWithPath: "/Users/x/.agents/skills/s"),
            allocatedSize: 500, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: "same", conflict: nil,
            managementStatus: .standalone
        )
        let referencedCopy = SkillRecord(
            name: "s", summary: "", url: URL(fileURLWithPath: "/Users/x/.cc-switch/skills/s"),
            allocatedSize: 500, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: "same", conflict: nil,
            managementStatus: .standalone
        )
        // A symlink skill in the Agent's own skills dir pointing at the cc-switch copy.
        let link = SkillRecord(
            name: "s", summary: "", url: URL(fileURLWithPath: "/Users/x/.codex/skills/s"),
            allocatedSize: 0, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: "same", conflict: nil,
            managementStatus: .standalone,
            symlinkTarget: URL(fileURLWithPath: "/Users/x/.cc-switch/skills/s"),
            isSymlinkBroken: false
        )
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: [:],
            hooks: [],
            skills: [realCopy, referencedCopy, link]
        )
        let unref = findings.first { $0.kind == .unreferencedSkill }
        // Only the .agents copy is dead weight; the cc-switch copy is referenced.
        XCTAssertEqual(unref?.subject, "1")
        XCTAssertEqual(unref?.byteCount, 500)
    }

    func testSoleRealSkillIsNeverFlaggedUnreferenced() {
        // A lone real skill with no duplicate elsewhere must not be flagged, even
        // though nothing symlinks to it — it may be the one true copy in use.
        let lone = skill(name: "solo", fingerprint: "unique", path: "/a/skills/solo", size: 10)
        let findings = AIHealthFindings.analyze(
            duplication: .init(groups: [], totalReclaimable: 0),
            sizesByPath: [:],
            hooks: [],
            skills: [lone]
        )
        XCTAssertFalse(findings.contains { $0.kind == .unreferencedSkill })
    }
}
