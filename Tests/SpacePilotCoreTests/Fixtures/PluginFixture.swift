import Foundation
@testable import SpacePilotCore

enum PluginSkillsEncoding {
    case directory(String)
    case paths([String])
}

final class PluginFixture: @unchecked Sendable {
    let tree: TemporaryTree
    let root: URL

    private init(tree: TemporaryTree, root: URL) {
        self.tree = tree
        self.root = root
    }

    static func make(
        name: String,
        version: String,
        skillNames: [String],
        extraSkillPaths: [String] = [],
        skillsEncoding: PluginSkillsEncoding? = nil
    ) throws -> PluginFixture {
        let tree = try TemporaryTree(files: [:])
        let root = tree.url.appending(path: name, directoryHint: .isDirectory)
        let manifestDirectory = root.appending(path: ".codex-plugin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let explicitPaths = skillNames.map { "skills/\($0)" } + extraSkillPaths
        let declaration = skillsEncoding ?? .paths(explicitPaths)
        let skillsJSON: Any
        switch declaration {
        case .directory(let path): skillsJSON = path
        case .paths(let paths): skillsJSON = paths
        }
        let manifest: [String: Any] = [
            "name": name,
            "version": version,
            "skills": skillsJSON,
            "dependencies": ["codex"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: manifestDirectory.appending(path: "plugin.json"))
        for skill in skillNames {
            let folder = root.appending(path: "skills/\(skill)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let content = "---\nname: \(skill)\ndescription: \(skill) from \(name)\n---\nInstructions"
            try Data(content.utf8).write(to: folder.appending(path: "SKILL.md"))
        }
        return PluginFixture(tree: tree, root: root)
    }
}
