import Foundation
@testable import SpacePilotCore

final class SkillFixtureRoots: @unchecked Sendable {
    let tree: TemporaryTree
    let skillRoots: [SkillRoot]

    private init(tree: TemporaryTree, skillRoots: [SkillRoot]) {
        self.tree = tree
        self.skillRoots = skillRoots
    }

    static func make(
        shared: [String: String] = [:],
        codex: [String: String] = [:],
        claude: [String: String] = [:]
    ) throws -> SkillFixtureRoots {
        let files: [String: Int] = [:]
        let tree = try TemporaryTree(files: files)
        try write(shared, beneath: tree.url.appending(path: ".agents/skills"))
        try write(codex, beneath: tree.url.appending(path: ".codex/skills"))
        try write(claude, beneath: tree.url.appending(path: ".claude/skills"))
        return SkillFixtureRoots(tree: tree, skillRoots: [
            SkillRoot(url: tree.url.appending(path: ".agents/skills"), scope: .sharedAgents),
            SkillRoot(url: tree.url.appending(path: ".codex/skills"), scope: .agentSpecific(agent: "Codex")),
            SkillRoot(url: tree.url.appending(path: ".claude/skills"), scope: .agentSpecific(agent: "Claude"))
        ])
    }

    private static func write(_ skills: [String: String], beneath root: URL) throws {
        for (name, body) in skills {
            let folder = root.appending(path: name, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let content = """
            ---
            name: \(name)
            description: Fixture skill \(name)
            ---
            \(body)
            """
            try Data(content.utf8).write(to: folder.appending(path: "SKILL.md"))
        }
    }
}

extension Collection where Element == SkillRecord {
    func first(named name: String) -> SkillRecord? {
        first { $0.name == name }
    }
}
