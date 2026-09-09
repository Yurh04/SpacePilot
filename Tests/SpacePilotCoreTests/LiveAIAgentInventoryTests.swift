import XCTest
@testable import SpacePilotCore

/// Explicitly opt-in, read-only integration check. Never installs or updates.
final class LiveAIAgentInventoryTests: XCTestCase {
    private struct AppLocator: AIApplicationLocating {
        let apps: [String: URL]
        func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? { apps[bundleIdentifier] }
        func applicationVersion(forBundleIdentifier bundleIdentifier: String) -> String? {
            apps[bundleIdentifier].flatMap { Bundle(url: $0) }?
                .infoDictionary?["CFBundleShortVersionString"] as? String
        }
    }

    func testLiveAgentStorageSkillsAndUpdateRoutes() async throws {
        guard ProcessInfo.processInfo.environment["SPACEPILOT_LIVE_AI_CHECK"] == "1" else {
            throw XCTSkip("Set SPACEPILOT_LIVE_AI_CHECK=1 for read-only local inventory")
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var apps: [String: URL] = [:]
        for root in [URL(fileURLWithPath: "/Applications"), home.appending(path: "Applications")] {
            for app in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
                if let id = Bundle(url: app)?.bundleIdentifier { apps[id] = app }
            }
        }
        let records = try await AIToolRegistry(applicationLocator: AppLocator(apps: apps)).discover(homeDirectory: home)
        let agents = AIAgentProjection(records: records)
        let storage = try AIAgentStorageScanner(access: LocalFileSystemAccess()).scan(agents: agents.localAgents)
        for agent in agents.localAgents {
            let snapshot = try XCTUnwrap(storage[agent.id])
            print("LIVE-STORAGE \(agent.id): \(snapshot.items.count) rows, \(snapshot.items.reduce(0) { $0 + $1.allocatedSize }) bytes, \(snapshot.coverageFailures.count) failures")
            if agent.id == "codex" {
                for name in ["sessions", "logs_2.sqlite", "thread_history_1.sqlite", "history.jsonl", "computer-use", "cache"] {
                    guard FileManager.default.fileExists(atPath: home.appending(path: ".codex/\(name)").path) else { continue }
                    let row = try XCTUnwrap(snapshot.items.first { $0.url.lastPathComponent == name })
                    print("LIVE-CODEX \(name): \(row.category) \(row.allocatedSize)")
                    XCTAssertGreaterThan(row.allocatedSize, 0)
                }
            }
        }
        let standalone = try await SkillScanner().scan(roots: SkillRoot.production(homeDirectory: home))
        let discovered = PluginRootDiscovery(access: LocalFileSystemAccess()).discover(homeDirectory: home)
        let pluginResult = try await PluginScanner(skillScanner: SkillScanner()).scan(
            roots: PluginRoot.production(homeDirectory: home, discoveredRoots: discovered.roots)
        )
        if let codex = agents.localAgents.first(where: { $0.id == "codex" }) {
            let detail = AIAgentDetailProjection(
                agent: codex, skills: standalone + pluginResult.skills, plugins: pluginResult.plugins,
                storageSnapshot: storage["codex"]
            )
            let provided = detail.skills.filter { $0.parentPluginID != nil }
            print("LIVE-CODEX-SKILLS \(detail.skills.count) skills, \(provided.count) plugin-provided")
            for skill in provided.prefix(5) {
                print("LIVE-SKILL \(skill.name): \(detail.sourcePluginName(for: skill) ?? "missing") \(skill.allocatedSize) bytes")
                XCTAssertNotNil(detail.sourcePluginName(for: skill))
            }
        }
        let inventory = AIUpdateAssetBuilder.inventory(
            snapshot: nil, managementProjection: AIManagementProjection(records: records),
            projectSkills: [], projectPlugins: []
        )
        for asset in inventory.assets where asset.key.kind == .cli {
            print("LIVE-UPDATE \(asset.displayName): \(asset.localVersion.selectedVersion ?? "unknown"), \(inventory.executionCapabilities[asset.key]?.manager.rawValue ?? "handoff")")
        }
        if ProcessInfo.processInfo.environment["SPACEPILOT_LIVE_AI_NETWORK"] == "1",
           let codex = inventory.assets.first(where: { $0.definitionID == "codex" }) {
            let checks = await AIUpdateChecker().check([codex])
            let check = try XCTUnwrap(checks.first)
            print("LIVE-VERSION-CHECK Codex: \(check.status), latest \(check.latestVersion ?? "unknown"), failure \(String(describing: check.failure))")
            XCTAssertNotNil(check.latestVersion)
        }
    }
}
