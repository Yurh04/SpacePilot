import XCTest
@testable import SpacePilotCore

final class AIAgentFamilyTests: XCTestCase {
    private var records: [AIToolRecord] {
        [
            AIToolRecord(id: "desktop", kind: .application, displayName: "ChatGPT",
                         owner: .tool(definitionID: "chatgpt"),
                         evidence: AIToolEvidence(
                            applicationURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
                            detectedVersion: "9.0.0", dataRoots: [URL(fileURLWithPath: "/fixture/chatgpt")])),
            AIToolRecord(id: "cli", kind: .cli, displayName: "Codex",
                         owner: .tool(definitionID: "codex"),
                         evidence: AIToolEvidence(
                            executableURL: URL(fileURLWithPath: "/usr/local/bin/codex"),
                            detectedVersion: "1.2.3", dataRoots: [URL(fileURLWithPath: "/fixture/.codex")]))
        ]
    }

    func testFamilyMergesDesktopAndCLIWithoutChangingSourceRecords() throws {
        let input = records
        let projection = AIAgentProjection(records: input)
        let agent = try XCTUnwrap(projection.localAgents.first)
        XCTAssertEqual(projection.localAgents.count, 1)
        XCTAssertEqual(agent.id, "chatgpt")
        XCTAssertEqual(agent.displayName, "ChatGPT")
        XCTAssertEqual(agent.definitionIDs, ["codex", "chatgpt"])
        XCTAssertEqual(agent.formFactors, [.application, .cli])
        XCTAssertEqual(agent.icon, .installedApplication(URL(fileURLWithPath: "/Applications/ChatGPT.app")))
        XCTAssertEqual(agent.detectedVersion, "1.2.3")
        XCTAssertEqual(agent.dataRoots.count, 2)
        XCTAssertTrue(projection.cliTools.isEmpty)
        XCTAssertEqual(agent, AIAgentProjection(records: input.reversed()).localAgents.first)
        XCTAssertEqual(input[1].owner, .tool(definitionID: "codex"))
        let inventory = AIUpdateAssetBuilder.inventory(
            snapshot: nil, managementProjection: AIManagementProjection(records: input),
            projectSkills: [], projectPlugins: []
        )
        let cli = try XCTUnwrap(inventory.assets.first { $0.key.kind == .cli })
        XCTAssertEqual(cli.definitionID, "codex")
        XCTAssertTrue(agent.contains(definitionID: cli.definitionID))
        XCTAssertFalse(agent.contains(definitionID: nil))
        XCTAssertFalse(agent.contains(definitionID: "claude"))
    }

    func testCodexOnlyStillAppearsInFamilyWithoutInventingDesktop() throws {
        let agent = try XCTUnwrap(AIAgentProjection(records: [records[1]]).localAgents.first)
        XCTAssertEqual(agent.id, "chatgpt")
        XCTAssertNil(agent.applicationURL)
        XCTAssertEqual(agent.formFactors, [.cli])
    }

    func testFamilyIncludesBothOwnersAndPluginChildrenButNotOtherAgents() throws {
        let agent = try XCTUnwrap(AIAgentProjection(records: records).localAgents.first)
        let plugins = ["codex", "chatgpt", "claude"].map { id in
            PluginRecord(name: id, version: nil, url: URL(fileURLWithPath: "/fixture/\(id)/plugin"),
                         source: id, allocatedSize: 10, owner: .tool(definitionID: id))
        }
        let skills = ["codex", "chatgpt", "claude"].map { id in skill(id, owner: .tool(definitionID: id)) }
            + [skill("bundled", owner: .plugin(pluginID: plugins[0].id.uuidString), parent: plugins[0].id)]
        let detail = AIAgentDetailProjection(agent: agent, skills: skills, plugins: plugins)
        XCTAssertEqual(Set(detail.skills.map(\.name)), ["codex", "chatgpt", "bundled"])
        XCTAssertEqual(Set(detail.plugins.map(\.name)), ["codex", "chatgpt"])
        let groups = GroupedSkillsProjection(skills: skills, plugins: plugins, discoveredToolIDs: ["codex", "chatgpt"])
        XCTAssertEqual(groups.groups.filter { $0.id == "tool:chatgpt" }.count, 1)
        XCTAssertFalse(groups.groups.contains { $0.id == "tool:codex" })
        XCTAssertEqual(Set(groups.skills(in: "tool:chatgpt").map(\.id)), Set(detail.skills.map(\.id)))
        XCTAssertEqual(Set(GroupedPluginsProjection(plugins: plugins).plugins(in: "tool:chatgpt").map(\.id)), Set(detail.plugins.map(\.id)))
        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "tool:codex", preferredOwnerFrom: nil, groups: groups.groups), "tool:chatgpt")
    }

    private func skill(_ name: String, owner: AIAssetOwner, parent: UUID? = nil) -> SkillRecord {
        SkillRecord(name: name, summary: "", url: URL(fileURLWithPath: "/fixture/skills/\(name)"),
                    allocatedSize: 1, scope: .sharedAgents, visibleAgents: [], parentPluginID: parent,
                    fingerprint: name, conflict: nil, managementStatus: .standalone, owner: owner)
    }
}
