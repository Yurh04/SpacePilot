import Foundation
@testable import SpacePilotCore

final class AcceptanceFixture: @unchecked Sendable {
    let tree: TemporaryTree
    let coordinator: ScanCoordinator
    let userDocument: URL

    private init(tree: TemporaryTree, coordinator: ScanCoordinator, userDocument: URL) {
        self.tree = tree
        self.coordinator = coordinator
        self.userDocument = userDocument
    }

    static func make() throws -> AcceptanceFixture {
        let tree = try TemporaryTree(files: [
            "Library/Caches/com.example.One/cache.bin": 31,
            "Library/Application Support/ExampleOne/state.db": 41,
            "Documents/Example One Project/report.txt": 53,
            ".codex/sessions/session.jsonl": 61,
            ".codex/logs/codex.log": 17,
            ".codex/cache/index.bin": 23,
            ".codex/config.toml": 11,
            ".claude/projects/demo/transcript.jsonl": 67,
            ".claude/debug/claude.log": 19,
            ".claude/settings.json": 13,
            "Library/Application Support/ChatGPT/state.db": 37,
            ".npm/_cacache/index.bin": 21,
            ".agents/skills/shared-tool/SKILL.md": 7,
            ".agents/skills/review/SKILL.md": 7,
            ".codex/skills/review/SKILL.md": 7,
            ".claude/skills/claude-tool/SKILL.md": 7,
            ".codex/skills/.system/system-tool/SKILL.md": 7
        ])
        try writeSkill(name: "shared-tool", description: "Shared tool", body: "Shared", at: tree.url.appending(path: ".agents/skills/shared-tool/SKILL.md"))
        try writeSkill(name: "review", description: "Shared review", body: "Shared behavior", at: tree.url.appending(path: ".agents/skills/review/SKILL.md"))
        try writeSkill(name: "review", description: "Codex review", body: "Codex behavior", at: tree.url.appending(path: ".codex/skills/review/SKILL.md"))
        try writeSkill(name: "claude-tool", description: "Claude tool", body: "Claude", at: tree.url.appending(path: ".claude/skills/claude-tool/SKILL.md"))
        try writeSkill(name: "system-tool", description: "System tool", body: "System", at: tree.url.appending(path: ".codex/skills/.system/system-tool/SKILL.md"))
        try writeApplication(name: "Example One", bundleID: "com.example.One", version: "1.0", home: tree.url)
        try writeApplication(name: "Example Two", bundleID: "com.example.Two", version: "2.0", home: tree.url)
        try writeApplication(name: "ChatGPT", bundleID: "com.openai.chat", version: "1.0", home: tree.url)
        try writePlugin(home: tree.url)

        let store = InMemorySnapshotStore()
        let coordinator = ScanCoordinator(homeDirectory: tree.url, store: store)
        return AcceptanceFixture(
            tree: tree,
            coordinator: coordinator,
            userDocument: tree.url.appending(path: "Documents/Example One Project/report.txt")
        )
    }

    private static func writeApplication(name: String, bundleID: String, version: String, home: URL) throws {
        let app = home.appending(path: "Applications/\(name).app", directoryHint: .isDirectory)
        let executable = app.appending(path: "Contents/MacOS/\(name.replacingOccurrences(of: " ", with: ""))")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 29).write(to: executable)
        let info: [String: Any] = [
            "CFBundleDisplayName": name,
            "CFBundleIdentifier": bundleID,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": executable.lastPathComponent
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appending(path: "Contents/Info.plist"))
    }

    private static func writePlugin(home: URL) throws {
        let root = home.appending(path: ".codex/plugins/cache/curated/product-design/0.1.52")
        let manifestDirectory = root.appending(path: ".codex-plugin")
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": "product-design",
            "version": "0.1.52",
            "skills": ["skills/index"],
            "dependencies": ["codex"]
        ]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: manifestDirectory.appending(path: "plugin.json"))
        let skillURL = root.appending(path: "skills/index/SKILL.md")
        try FileManager.default.createDirectory(at: skillURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try writeSkill(name: "index", description: "Product design", body: "Managed", at: skillURL)
    }

    private static func writeSkill(name: String, description: String, body: String, at url: URL) throws {
        let text = "---\nname: \(name)\ndescription: \(description)\n---\n\(body)"
        try Data(text.utf8).write(to: url)
    }
}
