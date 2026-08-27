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
}
