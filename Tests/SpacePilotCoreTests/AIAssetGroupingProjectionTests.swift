import XCTest
@testable import SpacePilotCore

final class AIAssetGroupingProjectionTests: XCTestCase {
    private let codexPluginID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    func testSkillsGroupByExplicitOwnershipAndLocationScope() throws {
        let project = AIProjectIdentity(displayName: "Repo", canonicalRootURL: URL(fileURLWithPath: "/tmp/repo"))
        let skills = [
            skill("shared", path: "/skills/shared", owner: .shared, location: .userGlobal),
            skill("global", path: "/skills/global", owner: .tool(definitionID: "codex"), location: .userGlobal),
            skill("project", path: "/skills/project", owner: .tool(definitionID: "codex"), location: .project(project)),
            skill("system", path: "/skills/system", owner: .tool(definitionID: "codex"), location: .system),
            skill("unknown", path: "/skills/unknown", owner: .unknown, location: .userGlobal)
        ].reversed()

        let projection = GroupedSkillsProjection(skills: Array(skills), plugins: [])

        XCTAssertEqual(projection.groups.map(\.id), [
            "shared:global",
            "tool:codex:global",
            "tool:codex:project:\(project.id)",
            "tool:codex:system",
            "unknown"
        ])
        XCTAssertEqual(projection.skills(in: "tool:codex:project:\(project.id)").map(\.name), ["project"])
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

        XCTAssertEqual(projection.groups.map(\.id), ["tool:codex:bundled", "unknown"])
        XCTAssertEqual(projection.skills(in: "tool:codex:bundled").map(\.name), ["bundled"])
        XCTAssertEqual(projection.skills(in: "unknown").map(\.name), ["orphan"])
    }

    func testDedupUsesCanonicalURLPlusOwnerAndLocationScope() {
        let shared = skill("alpha", path: "/same/root", owner: .shared, location: .userGlobal, size: 10)
        let sharedDuplicate = skill("zeta", path: "/same/root/", owner: .shared, location: .userGlobal, size: 999)
        let codexSameURL = skill("codex", path: "/same/root", owner: .tool(definitionID: "codex"), location: .userGlobal, size: 20)

        let projection = GroupedSkillsProjection(skills: [sharedDuplicate, codexSameURL, shared], plugins: [])

        XCTAssertEqual(projection.skills(in: "shared:global").map(\.name), ["alpha"])
        XCTAssertEqual(projection.skills(in: "tool:codex:global").map(\.name), ["codex"])
        XCTAssertEqual(projection.groups.first { $0.id == "shared:global" }?.allocatedSize, 10)
        XCTAssertEqual(projection.groups.first { $0.id == "tool:codex:global" }?.allocatedSize, 20)
    }

    func testPluginsGroupAndDeduplicateDeterministically() {
        let first = plugin("Alpha", path: "/plugins/shared", owner: .tool(definitionID: "codex"), size: 8)
        let duplicate = plugin("zeta", path: "/plugins/shared/", owner: .tool(definitionID: "codex"), size: 99)
        let shared = plugin("shared", path: "/plugins/shared-global", owner: .shared, size: 4)

        let forward = GroupedPluginsProjection(plugins: [duplicate, shared, first])
        let reverse = GroupedPluginsProjection(plugins: [first, shared, duplicate].reversed())

        XCTAssertEqual(forward.groups.map(\.id), reverse.groups.map(\.id))
        XCTAssertEqual(forward.plugins(in: "tool:codex:global").map(\.name), ["Alpha"])
        XCTAssertEqual(forward.groups.first { $0.id == "tool:codex:global" }?.itemCount, 1)
        XCTAssertEqual(forward.groups.first { $0.id == "tool:codex:global" }?.allocatedSize, 8)
    }

    func testSearchFiltersItemsWithoutChangingGroups() {
        let projection = GroupedSkillsProjection(skills: [
            skill("one", path: "/skills/one", owner: .shared, location: .userGlobal),
            skill("two", path: "/skills/two", owner: .shared, location: .userGlobal)
        ], plugins: [])

        XCTAssertEqual(projection.groups.map(\.id), ["shared:global"])
        XCTAssertEqual(projection.skills(in: "shared:global", matching: "two").map(\.name), ["two"])
        XCTAssertEqual(projection.groups.map(\.id), ["shared:global"])
    }

    func testResolverPreservesValidThenNearestOwnerThenFirst() {
        let groups = [
            AIAssetGroup(id: "shared:global", kind: .sharedGlobal, title: "Shared", detail: "Global", itemCount: 1, allocatedSize: 1),
            AIAssetGroup(id: "tool:codex:bundled", kind: .toolBundled(definitionID: "codex"), title: "Codex", detail: "Bundled", itemCount: 1, allocatedSize: 1)
        ]

        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "shared:global", preferredOwnerFrom: nil, groups: groups), "shared:global")
        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "missing", preferredOwnerFrom: "tool:codex:global", groups: groups), "tool:codex:bundled")
        XCTAssertEqual(GroupedSkillsProjection.resolvedSelection(current: "missing", preferredOwnerFrom: nil, groups: groups), "shared:global")
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
