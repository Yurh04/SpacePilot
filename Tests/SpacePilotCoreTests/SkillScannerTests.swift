import XCTest
@testable import SpacePilotCore

final class SkillScannerTests: XCTestCase {
    func testPreservesSharedCodexAndClaudeScopes() async throws {
        let roots = try SkillFixtureRoots.make(
            shared: ["lark-doc": "Shared instructions"],
            codex: ["imagegen": "Codex instructions"],
            claude: ["smart-debug": "Claude instructions"]
        )

        let records = try await SkillScanner().scan(roots: roots.skillRoots)

        XCTAssertEqual(records.first(named: "lark-doc")?.scope, .sharedAgents)
        XCTAssertEqual(records.first(named: "imagegen")?.scope, .agentSpecific(agent: "Codex"))
        XCTAssertEqual(records.first(named: "smart-debug")?.scope, .agentSpecific(agent: "Claude"))
        XCTAssertEqual(records.first(named: "lark-doc")?.summary, "Fixture skill lark-doc")
        XCTAssertEqual(records.first(named: "lark-doc")?.owner, .shared)
        XCTAssertEqual(records.first(named: "imagegen")?.owner, .tool(definitionID: "codex"))
        XCTAssertEqual(records.first(named: "smart-debug")?.owner, .tool(definitionID: "claude"))
        XCTAssertTrue(records.allSatisfy { $0.locationScope == .userGlobal })
    }

    func testScannerDoesNotTreatFolderWithoutManifestAsSkill() async throws {
        let tree = try TemporaryTree(files: [".codex/skills/incomplete/readme.txt": 20])
        let roots = [SkillRoot(url: tree.url.appending(path: ".codex/skills"), scope: .agentSpecific(agent: "Codex"))]

        let records = try await SkillScanner().scan(roots: roots)

        XCTAssertTrue(records.isEmpty)
    }

    func testProductionRootsComeFromKnownDefinitionsAndCollapseSharedOverlap() throws {
        let home = URL(fileURLWithPath: "/Users/test")

        let roots = SkillRoot.production(homeDirectory: home)

        let shared = roots.filter { $0.url.path == "/Users/test/.agents/skills" }
        XCTAssertEqual(shared.count, 1)
        XCTAssertEqual(shared.first?.owner, .shared)
        XCTAssertEqual(shared.first?.locationScope, .userGlobal)
        XCTAssertTrue(roots.contains { $0.url.path == "/Users/test/.codex/skills" && $0.owner == .tool(definitionID: "codex") })
        XCTAssertTrue(roots.contains { $0.url.path == "/Users/test/.claude/skills" && $0.owner == .tool(definitionID: "claude") })
        XCTAssertTrue(roots.contains { $0.url.path == "/Users/test/.codex/skills/.system" && $0.locationScope == .system })
    }

    func testProductionRootConflictingOwnersBecomeUnknownDeterministically() throws {
        let home = URL(fileURLWithPath: "/Users/test")
        let definitions = [
            AIToolDefinition(id: "alpha", displayName: "Alpha", skillRoots: [AIToolRootDescriptor(".tool/skills")]),
            AIToolDefinition(id: "beta", displayName: "Beta", skillRoots: [AIToolRootDescriptor(".tool/skills")])
        ]

        let roots = SkillRoot.production(homeDirectory: home, definitions: definitions)
        let conflict = roots.first { $0.url.path == "/Users/test/.tool/skills" }

        XCTAssertEqual(conflict?.owner, .unknown)
        XCTAssertEqual(conflict?.locationScope, .userGlobal)
    }

    // MARK: - Symlink dependency detection

    func testSymlinkedSkillRecordsTargetAndBrokenState() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotSymlink-\(UUID().uuidString)", directoryHint: .isDirectory)
        let store = root.appending(path: "store", directoryHint: .isDirectory)
        let skillsDir = root.appending(path: ".codex/skills", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // A real skill directory in the external store.
        let realSkill = store.appending(path: "linked-skill", directoryHint: .isDirectory)
        try fm.createDirectory(at: realSkill, withIntermediateDirectories: true)
        try Data("---\nname: linked-skill\ndescription: via link\n---\n".utf8)
            .write(to: realSkill.appending(path: "SKILL.md"))
        // A live symlink into it.
        try fm.createSymbolicLink(
            at: skillsDir.appending(path: "linked-skill", directoryHint: .isDirectory),
            withDestinationURL: realSkill
        )

        let records = try await SkillScanner().scan(
            roots: [SkillRoot(url: skillsDir, scope: .agentSpecific(agent: "Codex"))]
        )
        let linked = try XCTUnwrap(records.first { $0.name == "linked-skill" })
        XCTAssertNotNil(linked.symlinkTarget)
        XCTAssertFalse(linked.isSymlinkBroken)
        XCTAssertEqual(linked.symlinkTarget?.lastPathComponent, "linked-skill")
    }

    func testRealDirectorySkillHasNoSymlinkTarget() async throws {
        let roots = try SkillFixtureRoots.make(codex: ["plain": "Plain skill"])
        let records = try await SkillScanner().scan(roots: roots.skillRoots)
        let plain = try XCTUnwrap(records.first(named: "plain"))
        XCTAssertNil(plain.symlinkTarget)
        XCTAssertFalse(plain.isSymlinkBroken)
    }
}
