import XCTest
@testable import SpacePilotCore

final class AISectionFilterTests: XCTestCase {
    private func skill(name: String, path: String, summary: String = "") -> SkillRecord {
        SkillRecord(
            name: name, summary: summary, url: URL(fileURLWithPath: path),
            allocatedSize: 0, scope: .sharedAgents, visibleAgents: [],
            parentPluginID: nil, fingerprint: "fp", conflict: nil,
            managementStatus: .standalone
        )
    }

    private func plugin(name: String, path: String, source: String = "src") -> PluginRecord {
        PluginRecord(
            name: name, version: nil, url: URL(fileURLWithPath: path),
            source: source, allocatedSize: 0
        )
    }

    private func cli(name: String, path: String?, version: String? = nil) -> AIToolRecord {
        AIToolRecord(
            id: "cli:\(name)", kind: .cli, displayName: name,
            owner: .tool(definitionID: name),
            evidence: AIToolEvidence(
                executableURL: path.map { URL(fileURLWithPath: $0) },
                detectedVersion: version
            )
        )
    }

    func testEmptyQueryReturnsInputUnchanged() {
        let skills = [skill(name: "a", path: "/a"), skill(name: "b", path: "/b")]
        XCTAssertEqual(AISectionFilter.filterSkills(skills, query: "  ").map(\.name), ["a", "b"])
    }

    func testSkillsFilterMatchesNamePathAndSummary() {
        let skills = [
            skill(name: "codex-helper", path: "/x/one"),
            skill(name: "other", path: "/tools/codex"),
            skill(name: "docs", path: "/y", summary: "about codex")
        ]
        XCTAssertEqual(
            AISectionFilter.filterSkills(skills, query: "codex").map(\.name),
            ["codex-helper", "other", "docs"]
        )
        XCTAssertEqual(AISectionFilter.filterSkills(skills, query: "docs").map(\.name), ["docs"])
    }

    func testPluginsFilterMatchesNameSourceAndPath() {
        let plugins = [
            plugin(name: "design", path: "/p/one", source: "curated"),
            plugin(name: "other", path: "/curated/two", source: "raw")
        ]
        XCTAssertEqual(
            AISectionFilter.filterPlugins(plugins, query: "curated").map(\.name),
            ["design", "other"]
        )
    }

    func testToolsFilterMatchesNamePathAndVersion() {
        let tools = [
            cli(name: "codex", path: "/usr/bin/codex", version: "1.0"),
            cli(name: "aider", path: "/opt/aider", version: "9.9"),
            cli(name: "nopath", path: nil)
        ]
        XCTAssertEqual(AISectionFilter.filterTools(tools, query: "aider").map(\.displayName), ["aider"])
        XCTAssertEqual(AISectionFilter.filterTools(tools, query: "9.9").map(\.displayName), ["aider"])
        XCTAssertEqual(AISectionFilter.filterTools(tools, query: "/usr/bin").map(\.displayName), ["codex"])
    }
}
