import XCTest
@testable import SpacePilotCore

final class DeveloperAIProjectionGlobalListsTests: XCTestCase {
    private func skill(name: String, path: String, scope: SkillScope = .sharedAgents) -> SkillRecord {
        SkillRecord(
            name: name,
            summary: "summary",
            url: URL(fileURLWithPath: path),
            allocatedSize: 10,
            scope: scope,
            visibleAgents: ["Codex"],
            parentPluginID: nil,
            fingerprint: "fp-\(name)",
            conflict: nil,
            managementStatus: .standalone
        )
    }

    private func plugin(name: String, path: String) -> PluginRecord {
        PluginRecord(
            name: name,
            version: "1.0",
            url: URL(fileURLWithPath: path),
            source: "source",
            allocatedSize: 10
        )
    }

    func testAllSkillsIncludesSharedAndUnownedRecordsSortedDeterministically() throws {
        let shared = skill(name: "zeta", path: "/skills/zeta", scope: .sharedAgents)
        let owned = skill(name: "Alpha", path: "/skills/alpha", scope: .agentSpecific(agent: "Codex"))
        let system = skill(name: "beta", path: "/skills/beta", scope: .systemManaged)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [shared, owned, system],
            coverage: .complete,
            pluginDiagnostics: []
        )

        let projection = try DeveloperAIProjection(snapshot: snapshot, checkCancellation: {})

        XCTAssertEqual(projection.allSkills.map(\.name), ["Alpha", "beta", "zeta"])
    }

    func testAllPluginsIncludesEveryPluginSortedDeterministically() throws {
        let one = plugin(name: "Bravo", path: "/plugins/bravo")
        let two = plugin(name: "alpha", path: "/plugins/alpha")
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: [],
            plugins: [one, two],
            skills: [],
            coverage: .complete,
            pluginDiagnostics: []
        )

        let projection = try DeveloperAIProjection(snapshot: snapshot, checkCancellation: {})

        XCTAssertEqual(projection.allPlugins.map(\.name), ["alpha", "Bravo"])
    }

    func testGlobalListsAreStableAcrossInputOrder() throws {
        let a = skill(name: "same", path: "/skills/a")
        let b = skill(name: "same", path: "/skills/b")
        let snapshotForward = ScanSnapshot(
            completedAt: .now, volume: nil, items: [], applications: [],
            aiApplications: [], plugins: [], skills: [a, b],
            coverage: .complete, pluginDiagnostics: []
        )
        let snapshotReversed = ScanSnapshot(
            completedAt: .now, volume: nil, items: [], applications: [],
            aiApplications: [], plugins: [], skills: [b, a],
            coverage: .complete, pluginDiagnostics: []
        )

        let forward = try DeveloperAIProjection(snapshot: snapshotForward, checkCancellation: {})
        let reversed = try DeveloperAIProjection(snapshot: snapshotReversed, checkCancellation: {})

        XCTAssertEqual(forward.allSkills.map(\.id), reversed.allSkills.map(\.id))
    }

    func testAllSkillsDeduplicatesByCanonicalURLAcrossDistinctIDs() throws {
        // Two SkillRecords with different random UUIDs but the same canonical URL
        // (one uses a trailing-slash form) must collapse to a single global row.
        let first = skill(name: "shared", path: "/agents/skills/shared")
        let second = skill(name: "shared", path: "/agents/skills/shared/")
        let snapshot = ScanSnapshot(
            completedAt: .now, volume: nil, items: [], applications: [],
            aiApplications: [], plugins: [], skills: [first, second],
            coverage: .complete, pluginDiagnostics: []
        )

        let projection = try DeveloperAIProjection(snapshot: snapshot, checkCancellation: {})

        XCTAssertEqual(projection.allSkills.count, 1)
    }

    func testSkillDuplicateSurvivorIsDeterministicRegardlessOfInputOrder() throws {
        // Same canonical URL, different name AND different UUID: the survivor must
        // be identical no matter the snapshot input order.
        let alpha = skill(name: "Alpha", path: "/agents/skills/shared")
        let zeta = skill(name: "zeta", path: "/agents/skills/shared/")

        let forward = try DeveloperAIProjection(
            snapshot: ScanSnapshot(
                completedAt: .now, volume: nil, items: [], applications: [],
                aiApplications: [], plugins: [], skills: [alpha, zeta],
                coverage: .complete, pluginDiagnostics: []
            ),
            checkCancellation: {}
        )
        let reversed = try DeveloperAIProjection(
            snapshot: ScanSnapshot(
                completedAt: .now, volume: nil, items: [], applications: [],
                aiApplications: [], plugins: [], skills: [zeta, alpha],
                coverage: .complete, pluginDiagnostics: []
            ),
            checkCancellation: {}
        )

        XCTAssertEqual(forward.allSkills.count, 1)
        XCTAssertEqual(forward.allSkills.map(\.id), reversed.allSkills.map(\.id))
        XCTAssertEqual(forward.allSkills.map(\.name), reversed.allSkills.map(\.name))
        // Stable total order tie-breaks by case-insensitive name: "Alpha" wins.
        XCTAssertEqual(forward.allSkills.first?.name, "Alpha")
    }

    func testAllPluginsDeduplicatesByCanonicalURLAcrossDistinctIDs() throws {
        let first = plugin(name: "dup", path: "/plugins/dup")
        let second = plugin(name: "dup", path: "/plugins/dup/")
        let snapshot = ScanSnapshot(
            completedAt: .now, volume: nil, items: [], applications: [],
            aiApplications: [], plugins: [first, second], skills: [],
            coverage: .complete, pluginDiagnostics: []
        )

        let projection = try DeveloperAIProjection(snapshot: snapshot, checkCancellation: {})

        XCTAssertEqual(projection.allPlugins.count, 1)
    }

    func testPluginDuplicateSurvivorIsDeterministicRegardlessOfInputOrder() throws {
        let alpha = plugin(name: "Alpha", path: "/plugins/shared")
        let zeta = plugin(name: "zeta", path: "/plugins/shared/")

        let forward = try DeveloperAIProjection(
            snapshot: ScanSnapshot(
                completedAt: .now, volume: nil, items: [], applications: [],
                aiApplications: [], plugins: [alpha, zeta], skills: [],
                coverage: .complete, pluginDiagnostics: []
            ),
            checkCancellation: {}
        )
        let reversed = try DeveloperAIProjection(
            snapshot: ScanSnapshot(
                completedAt: .now, volume: nil, items: [], applications: [],
                aiApplications: [], plugins: [zeta, alpha], skills: [],
                coverage: .complete, pluginDiagnostics: []
            ),
            checkCancellation: {}
        )

        XCTAssertEqual(forward.allPlugins.count, 1)
        XCTAssertEqual(forward.allPlugins.map(\.id), reversed.allPlugins.map(\.id))
        XCTAssertEqual(forward.allPlugins.first?.name, "Alpha")
    }

    func testDistinctURLsAreNotDeduplicated() throws {
        let a = plugin(name: "a", path: "/plugins/a")
        let b = plugin(name: "b", path: "/plugins/b")
        let snapshot = ScanSnapshot(
            completedAt: .now, volume: nil, items: [], applications: [],
            aiApplications: [], plugins: [a, b], skills: [],
            coverage: .complete, pluginDiagnostics: []
        )

        let projection = try DeveloperAIProjection(snapshot: snapshot, checkCancellation: {})

        XCTAssertEqual(projection.allPlugins.count, 2)
    }
}
