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
}
