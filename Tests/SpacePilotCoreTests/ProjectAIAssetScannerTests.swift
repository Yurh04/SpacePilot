import XCTest
@testable import SpacePilotCore

final class ProjectAIAssetScannerTests: XCTestCase {
    func testScansOnlyFixedProjectDescriptorsWithExplicitOwnersAndProjectScope() async throws {
        let tree = try TemporaryTree(files: [:])
        let project = tree.url.appending(path: "MyProject", directoryHint: .isDirectory)
        try writeSkill(named: "shared-skill", beneath: project.appending(path: ".agents/skills"))
        try writeSkill(named: "codex-skill", beneath: project.appending(path: ".codex/skills"))
        try writeSkill(named: "ignored", beneath: project.appending(path: "random/skills"))
        try writePlugin(
            named: "codex-plugin",
            beneath: project.appending(path: ".codex/plugins", directoryHint: .isDirectory),
            skill: "plugin-skill"
        )
        let root = ApprovedProjectRoot(canonicalRootURL: project)

        let result = try await ProjectAIAssetScanner(skillScanner: SkillScanner()).scan(approvedRoots: [root])

        XCTAssertEqual(Set(result.skills.map(\.name)), ["shared-skill", "codex-skill", "plugin-skill"])
        XCTAssertEqual(result.skills.first(named: "shared-skill")?.owner, .shared)
        XCTAssertEqual(result.skills.first(named: "codex-skill")?.owner, .tool(definitionID: "codex"))
        XCTAssertEqual(result.skills.first(named: "shared-skill")?.locationScope, .project(root.identity))
        let plugin = try XCTUnwrap(result.plugins.first)
        XCTAssertEqual(plugin.owner, .tool(definitionID: "codex"))
        XCTAssertEqual(plugin.locationScope, .project(root.identity))
        XCTAssertEqual(result.skills.first(named: "plugin-skill")?.parentPluginID, plugin.id)
        XCTAssertEqual(result.skills.first(named: "plugin-skill")?.locationScope, .bundled)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testDescriptorValidationRejectsAbsoluteDotDotAndSymlinkEscapes() async throws {
        let tree = try TemporaryTree(files: [:])
        let project = tree.url.appending(path: "Project", directoryHint: .isDirectory)
        let outside = tree.url.appending(path: "Outside", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside.appending(path: "skills"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: project.appending(path: ".escape"), withDestinationURL: outside)
        let root = ApprovedProjectRoot(canonicalRootURL: project)
        let definitions = [AIToolDefinition(
            id: "bad",
            displayName: "Bad",
            projectAssetDescriptors: [
                AIProjectAssetDescriptor("/absolute", kind: .skills),
                AIProjectAssetDescriptor("../outside", kind: .skills),
                AIProjectAssetDescriptor(".escape/skills", kind: .skills)
            ]
        )]

        let result = try await ProjectAIAssetScanner(skillScanner: SkillScanner(), definitions: definitions)
            .scan(approvedRoots: [root])

        XCTAssertTrue(result.skills.isEmpty)
        XCTAssertTrue(result.plugins.isEmpty)
        XCTAssertTrue(result.issues.contains(.invalidDescriptor))
        XCTAssertTrue(result.issues.contains(.descriptorEscapesProjectRoot))
    }

    func testPluginProvidedSkillGroupsUnderSameProject() async throws {
        let tree = try TemporaryTree(files: [:])
        let project = tree.url.appending(path: "Project", directoryHint: .isDirectory)
        try writePlugin(
            named: "project-plugin",
            beneath: project.appending(path: ".codex/plugins", directoryHint: .isDirectory),
            skill: "child-skill"
        )
        let root = ApprovedProjectRoot(canonicalRootURL: project)
        let result = try await ProjectAIAssetScanner(skillScanner: SkillScanner()).scan(approvedRoots: [root])

        let grouped = GroupedSkillsProjection(skills: result.skills, plugins: result.plugins)

        // The plugin-provided skill aggregates under the Codex tool owner and
        // keeps its project scope (not the global "bundled" scope).
        XCTAssertTrue(grouped.groups.contains { $0.kind == .tool(definitionID: "codex") })
        let codexSkills = grouped.skills(in: "tool:codex")
        XCTAssertEqual(codexSkills.map(\.name), ["child-skill"])
        let childSkill = try XCTUnwrap(codexSkills.first)
        XCTAssertEqual(grouped.scopeDetail(for: childSkill), .project(root.identity))
    }

    private func writeSkill(named name: String, beneath root: URL) throws {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let content = "---\nname: \(name)\ndescription: Project skill\n---\nInstructions"
        try Data(content.utf8).write(to: folder.appending(path: "SKILL.md"))
    }

    private func writePlugin(named name: String, beneath container: URL, skill: String) throws {
        let root = container.appending(path: name, directoryHint: .isDirectory)
        let manifest = root.appending(path: ".codex-plugin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifest, withIntermediateDirectories: true)
        let json: [String: Any] = ["name": name, "version": "1", "skills": ["skills/\(skill)"]]
        try JSONSerialization.data(withJSONObject: json)
            .write(to: manifest.appending(path: "plugin.json"))
        try writeSkill(named: skill, beneath: root.appending(path: "skills"))
    }
}
