import XCTest
@testable import SpacePilotCore

final class AIAssetGroupingProjectionTests: XCTestCase {
    private let codexPluginID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testSkillsGroupByOwnerFirstWithScopeAvailablePerRow() throws {
        let project = AIProjectIdentity(displayName: "Repo", canonicalRootURL: URL(fileURLWithPath: "/tmp/repo"))
        let skills = [
            skill("shared", path: "/skills/shared", owner: .shared, location: .userGlobal),
            skill("shared-project", path: "/skills/shared-project", owner: .shared, location: .project(project)),
            skill("global", path: "/skills/global", owner: .tool(definitionID: "codex"), location: .userGlobal),
            skill("project", path: "/skills/project", owner: .tool(definitionID: "codex"), location: .project(project)),
            skill("system", path: "/skills/system", owner: .tool(definitionID: "codex"), location: .system),
            skill("unknown", path: "/skills/unknown", owner: .unknown, location: .userGlobal)
        ].reversed()

        let projection = GroupedSkillsProjection(skills: Array(skills), plugins: [])

        // First level is owner-only: Shared, one entry per tool, then Unknown.
        XCTAssertEqual(projection.groups.map(\.id), ["shared", "tool:codex", "unknown"])
        XCTAssertEqual(projection.groups.first { $0.id == "tool:codex" }?.title, "Codex")
        XCTAssertEqual(projection.groups.first { $0.id == "tool:codex" }?.itemCount, 3)

        // All of a tool's skills appear under its single entry across scopes.
        XCTAssertEqual(projection.skills(in: "tool:codex").map(\.name), ["global", "project", "system"])
        XCTAssertEqual(projection.skills(in: "shared").map(\.name), ["shared", "shared-project"])

        // Scope is exposed per row for the right-pane column/filter.
        let projectSkill = try XCTUnwrap(projection.skills(in: "tool:codex").first { $0.name == "project" })
        XCTAssertEqual(projection.scopeDetail(for: projectSkill), .project(project))
        let systemSkill = try XCTUnwrap(projection.skills(in: "tool:codex").first { $0.name == "system" })
        XCTAssertEqual(projection.scopeDetail(for: systemSkill), .system)
        let sharedProject = try XCTUnwrap(projection.skills(in: "shared").first { $0.name == "shared-project" })
        XCTAssertEqual(projection.scopeDetail(for: sharedProject), .project(project))
    }

    func testEmptyOwnersProduceNoSidebarEntries() {
        let projection = GroupedSkillsProjection(skills: [
            skill("only", path: "/skills/only", owner: .tool(definitionID: "codex"), location: .userGlobal)
        ], plugins: [])

        // Only owners with assets appear; no empty Shared/Unknown rows.
        XCTAssertEqual(projection.groups.map(\.id), ["tool:codex"])
    }

    func testPluginProvidedSkillGroupsUnderParentPluginToolOwner() {
        let plugin = PluginRecord(
            id: codexPluginID,
            name: "codex-plugin",
            version: nil,
            url: URL(fileURLWithPath: "/plugins/codex"),
            source: "codex",
            allocatedSize: 3,
            owner: .tool(definitionID: "codex"),
            locationScope: .userGlobal
        )
        let bundled = skill(
            "bundled",
            path: "/plugins/codex/skills/bundled",
            owner: .plugin(pluginID: codexPluginID.uuidString),
            location: .bundled,
            parentPluginID: codexPluginID
        )
        let orphan = skill(
            "orphan",
            path: "/plugins/orphan/skills/orphan",
            owner: .plugin(pluginID: "missing"),
            location: .bundled,
            parentPluginID: UUID()
        )

        let projection = GroupedSkillsProjection(skills: [orphan, bundled], plugins: [plugin])

        XCTAssertEqual(projection.groups.map(\.id), ["tool:codex", "unknown"])
        XCTAssertEqual(projection.skills(in: "tool:codex").map(\.name), ["bundled"])
        XCTAssertEqual(projection.skills(in: "unknown").map(\.name), ["orphan"])
        XCTAssertEqual(projection.scopeDetail(for: bundled), .bundled)
    }

    func testProjectPluginProvidedSkillKeepsProjectScope() {
        let project = AIProjectIdentity(displayName: "Repo", canonicalRootURL: URL(fileURLWithPath: "/tmp/repo"))
        let plugin = PluginRecord(
            id: codexPluginID,
            name: "project-plugin",
            version: nil,
            url: URL(fileURLWithPath: "/repo/.codex/plugins/project-plugin"),
            source: "codex",
            allocatedSize: 3,
            owner: .tool(definitionID: "codex"),
            locationScope: .project(project)
        )
        let child = skill(
            "child",
            path: "/repo/.codex/plugins/project-plugin/skills/child",
            owner: .plugin(pluginID: codexPluginID.uuidString),
            location: .bundled,
            parentPluginID: codexPluginID
        )

        let projection = GroupedSkillsProjection(skills: [child], plugins: [plugin])

        XCTAssertEqual(projection.groups.map(\.id), ["tool:codex"])
        XCTAssertEqual(projection.scopeDetail(for: child), .project(project))
    }

    func testDedupUsesCanonicalURLPlusOwnerAndLocationScope() {
        let shared = skill("alpha", path: "/same/root", owner: .shared, location: .userGlobal, size: 10)
        let sharedDuplicate = skill("zeta", path: "/same/root/", owner: .shared, location: .userGlobal, size: 999)
        let codexSameURL = skill("codex", path: "/same/root", owner: .tool(definitionID: "codex"), location: .userGlobal, size: 20)

        let projection = GroupedSkillsProjection(skills: [sharedDuplicate, codexSameURL, shared], plugins: [])

        XCTAssertEqual(projection.skills(in: "shared").map(\.name), ["alpha"])
        XCTAssertEqual(projection.skills(in: "tool:codex").map(\.name), ["codex"])
        XCTAssertEqual(projection.groups.first { $0.id == "shared" }?.allocatedSize, 10)
        XCTAssertEqual(projection.groups.first { $0.id == "tool:codex" }?.allocatedSize, 20)
    }

    func testPluginsGroupAndDeduplicateDeterministically() {
        let first = plugin("Alpha", path: "/plugins/shared", owner: .tool(definitionID: "codex"), size: 8)
        let duplicate = plugin("zeta", path: "/plugins/shared/", owner: .tool(definitionID: "codex"), size: 99)
        let shared = plugin("shared", path: "/plugins/shared-global", owner: .shared, size: 4)

        let forward = GroupedPluginsProjection(plugins: [duplicate, shared, first])
        let reverse = GroupedPluginsProjection(plugins: [first, shared, duplicate].reversed())

        XCTAssertEqual(forward.groups.map(\.id), reverse.groups.map(\.id))
        XCTAssertEqual(forward.groups.map(\.id), ["shared", "tool:codex"])
        XCTAssertEqual(forward.plugins(in: "tool:codex").map(\.name), ["Alpha"])
        XCTAssertEqual(forward.groups.first { $0.id == "tool:codex" }?.itemCount, 1)
        XCTAssertEqual(forward.groups.first { $0.id == "tool:codex" }?.allocatedSize, 8)
    }

    func testSearchFiltersItemsWithoutChangingGroups() {
        let projection = GroupedSkillsProjection(skills: [
            skill("one", path: "/skills/one", owner: .shared, location: .userGlobal),
            skill("two", path: "/skills/two", owner: .shared, location: .userGlobal)
        ], plugins: [])

        XCTAssertEqual(projection.groups.map(\.id), ["shared"])
        XCTAssertEqual(projection.skills(in: "shared", matching: "two").map(\.name), ["two"])
        XCTAssertEqual(projection.groups.map(\.id), ["shared"])
    }

    func testResolverPreservesValidThenNearestOwnerThenFirst() {
        let groups = [
            AIAssetGroup(id: "shared", kind: .shared, title: "Shared", itemCount: 1, allocatedSize: 1),
            AIAssetGroup(id: "tool:codex", kind: .tool(definitionID: "codex"), title: "Codex", itemCount: 1, allocatedSize: 1)
        ]

        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "shared", preferredOwnerFrom: nil, groups: groups), "shared")
        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "missing", preferredOwnerFrom: "tool:codex", groups: groups), "tool:codex")
        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "missing", preferredOwnerFrom: nil, groups: groups), "shared")
        XCTAssertNil(GroupedSkillsProjection.resolvedSelection(current: nil, preferredOwnerFrom: nil, groups: []))
    }

    private func skill(
        _ name: String,
        path: String,
        owner: AIAssetOwner,
        location: AIAssetLocationScope,
        parentPluginID: UUID? = nil,
        size: Int64 = 1
    ) -> SkillRecord {
        SkillRecord(
            name: name,
            summary: "summary",
            url: URL(fileURLWithPath: path),
            allocatedSize: size,
            scope: .sharedAgents,
            visibleAgents: ["Codex"],
            parentPluginID: parentPluginID,
            fingerprint: "fp-\(name)",
            conflict: nil,
            managementStatus: .standalone,
            owner: owner,
            locationScope: location
        )
    }

    private func plugin(
        _ name: String,
        path: String,
        owner: AIAssetOwner,
        size: Int64
    ) -> PluginRecord {
        PluginRecord(
            name: name,
            version: "1",
            url: URL(fileURLWithPath: path),
            source: "source",
            allocatedSize: size,
            owner: owner,
            locationScope: .userGlobal
        )
    }
}
