import XCTest
@testable import SpacePilotCore

/// 6A regression coverage for the unified AI Agent model: projection join /
/// local-vs-remote split / CLI-Tools exclusion, icon precedence, the detail
/// projection, and temp-home fixtures proving per-Agent skill/plugin discovery.
final class AIAgentProjectionTests: XCTestCase {

    // MARK: - Helpers

    private func toolRecord(
        kind: AIToolKind,
        definitionID: String,
        displayName: String,
        evidence: AIToolEvidence,
        canonical: String
    ) -> AIToolRecord {
        AIToolRecord(
            id: AIToolRecord.stableID(kind: kind, owner: .tool(definitionID: definitionID), canonicalLocation: canonical),
            kind: kind,
            displayName: displayName,
            owner: .tool(definitionID: definitionID),
            evidence: evidence
        )
    }

    // MARK: - Icon precedence

    func testIconPrecedenceInstalledAppBeatsBundledBeatsSymbol() {
        let app = URL(fileURLWithPath: "/Applications/Foo.app")
        let resolved = AgentIconDescriptor.resolve(from: [
            .systemSymbol(name: "gear"),
            .bundledAsset(name: "foo"),
            .installedApplication(app)
        ])
        XCTAssertEqual(resolved, .installedApplication(app))

        let noApp = AgentIconDescriptor.resolve(from: [
            .systemSymbol(name: "gear"),
            .bundledAsset(name: "foo")
        ])
        XCTAssertEqual(noApp, .bundledAsset(name: "foo"))

        let symbolOnly = AgentIconDescriptor.resolve(from: [.systemSymbol(name: "gear")])
        XCTAssertEqual(symbolOnly, .systemSymbol(name: "gear"))
    }

    func testIconResolutionIsOrderIndependent() {
        let app = URL(fileURLWithPath: "/Applications/Bar.app")
        let a = AgentIconDescriptor.resolve(from: [.installedApplication(app), .bundledAsset(name: "b"), .systemSymbol(name: "s")])
        let b = AgentIconDescriptor.resolve(from: [.systemSymbol(name: "s"), .bundledAsset(name: "b"), .installedApplication(app)])
        XCTAssertEqual(a, b)
    }

    // MARK: - Projection join & split

    func testApplicationAndCLIForSameDefinitionMergeIntoOneAgent() {
        let appURL = URL(fileURLWithPath: "/Applications/Claude.app")
        let exeURL = URL(fileURLWithPath: "/usr/local/bin/claude")
        let records = [
            toolRecord(
                kind: .application, definitionID: "claude", displayName: "Claude",
                evidence: AIToolEvidence(applicationURL: appURL), canonical: appURL.path
            ),
            toolRecord(
                kind: .cli, definitionID: "claude", displayName: "Claude",
                evidence: AIToolEvidence(executableURL: exeURL, detectedVersion: "1.2.3"), canonical: exeURL.path
            )
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertEqual(projection.localAgents.count, 1)
        let claude = try? XCTUnwrap(projection.localAgents.first)
        XCTAssertEqual(claude?.id, "claude")
        XCTAssertEqual(claude?.applicationURL, appURL)
        XCTAssertEqual(claude?.executableURL, exeURL)
        XCTAssertEqual(claude?.detectedVersion, "1.2.3")
        XCTAssertEqual(claude?.formFactors, [.application, .cli])
        XCTAssertEqual(claude?.icon, .installedApplication(appURL))
    }

    func testAidenIsLocalAgentAndNotACLITool() {
        let exeURL = URL(fileURLWithPath: "/Users/x/Library/pnpm/bin/aiden")
        let records = [
            toolRecord(kind: .cli, definitionID: "aiden", displayName: "Aiden",
                       evidence: AIToolEvidence(executableURL: exeURL), canonical: exeURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertEqual(projection.localAgents.map(\.id), ["aiden"])
        XCTAssertTrue(projection.remoteAgents.isEmpty)
        XCTAssertFalse(projection.cliTools.contains { $0.displayName == "Aiden" })
    }

    func testTraexIsRemoteAgentAndNotCLITool() {
        let exeURL = URL(fileURLWithPath: "/Users/x/.local/share/traex/current/traex")
        let records = [
            toolRecord(kind: .cli, definitionID: "traex", displayName: "Traex",
                       evidence: AIToolEvidence(executableURL: exeURL), canonical: exeURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertEqual(projection.remoteAgents.map(\.id), ["traex"])
        XCTAssertTrue(projection.localAgents.isEmpty)
        XCTAssertFalse(projection.cliTools.contains { $0.displayName == "Traex" })
        XCTAssertEqual(projection.remoteAgents.first?.locality, .remote)
    }

    func testSupportingCLIStaysInCLIToolsAndNotInAgents() {
        let exeURL = URL(fileURLWithPath: "/opt/homebrew/bin/lark-cli")
        let records = [
            toolRecord(kind: .cli, definitionID: "lark-cli", displayName: "Lark CLI",
                       evidence: AIToolEvidence(executableURL: exeURL), canonical: exeURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertTrue(projection.localAgents.isEmpty)
        XCTAssertTrue(projection.remoteAgents.isEmpty)
        XCTAssertEqual(projection.cliTools.map(\.displayName), ["Lark CLI"])
    }

    func testConfigOnlyFootprintDoesNotFabricateAgent() {
        // A skill record alone (no app / executable) must not create an Agent.
        let skillURL = URL(fileURLWithPath: "/Users/x/.codex/skills/foo")
        let records = [
            toolRecord(kind: .skill, definitionID: "codex", displayName: "Codex",
                       evidence: AIToolEvidence(skillRoots: [skillURL]), canonical: skillURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertTrue(projection.localAgents.isEmpty)
        XCTAssertTrue(projection.remoteAgents.isEmpty)
    }

    func testProjectionOrderingIsInputOrderIndependent() {
        let codex = toolRecord(kind: .cli, definitionID: "codex", displayName: "Codex",
                               evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: "/bin/codex")), canonical: "/bin/codex")
        let claude = toolRecord(kind: .cli, definitionID: "claude", displayName: "Claude",
                                evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: "/bin/claude")), canonical: "/bin/claude")
        let a = AIAgentProjection(records: [codex, claude]).localAgents.map(\.id)
        let b = AIAgentProjection(records: [claude, codex]).localAgents.map(\.id)
        XCTAssertEqual(a, b)
        // Catalog order places codex before claude.
        XCTAssertEqual(a, ["codex", "claude"])
    }

    // MARK: - Detail projection

    func testRemoteAgentDetailModulesAreNotApplicable() {
        let entry = AIAgentEntry(
            id: "traex", displayName: "Traex", locality: .remote,
            formFactors: [.cloud], icon: .systemSymbol(name: "cloud")
        )
        let detail = AIAgentDetailProjection(agent: entry, skills: [], plugins: [])
        XCTAssertEqual(detail.storageAvailability, .notApplicable)
        XCTAssertEqual(detail.skillsAvailability, .notApplicable)
        XCTAssertEqual(detail.pluginsAvailability, .notApplicable)
    }

    func testLocalAgentKeepsEmptyModules() {
        let entry = AIAgentEntry(
            id: "codex", displayName: "Codex", locality: .local,
            formFactors: [.cli], icon: .systemSymbol(name: "terminal"),
            dataRoots: [URL(fileURLWithPath: "/Users/x/.codex")]
        )
        let detail = AIAgentDetailProjection(agent: entry, skills: [], plugins: [])
        XCTAssertEqual(detail.storageAvailability, .available)
        XCTAssertEqual(detail.skillsAvailability, .empty)
        XCTAssertEqual(detail.pluginsAvailability, .empty)
        XCTAssertEqual(detail.storageItems.count, 1)
    }

    /// Owned skills and shared skills are reported through separate channels: a
    /// per-Agent module must never silently mix them, because deleting a shared
    /// skill affects every Agent while deleting an owned one does not. The UI
    /// offers an explicit "this Agent" / "Global" switch over these two lists.
    func testDetailProjectionSeparatesOwnedSkillsFromSharedSkills() {
        let entry = AIAgentEntry(
            id: "codex", displayName: "Codex", locality: .local,
            formFactors: [.cli], icon: .systemSymbol(name: "terminal")
        )
        let mine = SkillRecord(
            name: "Mine", summary: "", url: URL(fileURLWithPath: "/Users/x/.codex/skills/mine"),
            allocatedSize: 0, scope: .agentSpecific(agent: "Codex"), visibleAgents: ["Codex"],
            parentPluginID: nil, fingerprint: "a", conflict: nil, managementStatus: .standalone,
            owner: .tool(definitionID: "codex"), locationScope: .userGlobal
        )
        let shared = SkillRecord(
            name: "Shared", summary: "", url: URL(fileURLWithPath: "/Users/x/.agents/skills/shared"),
            allocatedSize: 0, scope: .sharedAgents, visibleAgents: ["Codex", "Claude"],
            parentPluginID: nil, fingerprint: "b", conflict: nil, managementStatus: .standalone,
            owner: .shared, locationScope: .userGlobal
        )
        let other = SkillRecord(
            name: "Other", summary: "", url: URL(fileURLWithPath: "/Users/x/.claude/skills/other"),
            allocatedSize: 0, scope: .agentSpecific(agent: "Claude"), visibleAgents: ["Claude"],
            parentPluginID: nil, fingerprint: "c", conflict: nil, managementStatus: .standalone,
            owner: .tool(definitionID: "claude"), locationScope: .userGlobal
        )
        let detail = AIAgentDetailProjection(agent: entry, skills: [mine, shared, other], plugins: [])
        // "This Agent" holds only what this Agent owns — never shared, never
        // another Agent's.
        XCTAssertEqual(detail.skills.map(\.name), ["Mine"])
        XCTAssertEqual(detail.skillsAvailability, .available)
        // "Global" surfaces the shared skill, so it is reachable from the Agent
        // without being counted as the Agent's own.
        XCTAssertEqual(detail.globalSkills.map(\.name), ["Shared"])
        XCTAssertEqual(detail.globalSkillsAvailability, .available)
        // Another Agent's owned skill appears in neither list.
        XCTAssertFalse(detail.skills.contains { $0.name == "Other" })
        XCTAssertFalse(detail.globalSkills.contains { $0.name == "Other" })
    }

    /// Remote Agents manage no local assets, so both skill channels report
    /// `.notApplicable` rather than a misleading empty list.
    func testRemoteAgentReportsGlobalSkillsNotApplicable() {
        let entry = AIAgentEntry(
            id: "traex", displayName: "Traex", locality: .remote,
            formFactors: [.cloud], icon: .systemSymbol(name: "cloud")
        )
        let shared = SkillRecord(
            name: "Shared", summary: "", url: URL(fileURLWithPath: "/Users/x/.agents/skills/shared"),
            allocatedSize: 0, scope: .sharedAgents, visibleAgents: ["Codex"],
            parentPluginID: nil, fingerprint: "b", conflict: nil, managementStatus: .standalone,
            owner: .shared, locationScope: .userGlobal
        )
        let detail = AIAgentDetailProjection(agent: entry, skills: [shared], plugins: [])
        XCTAssertTrue(detail.globalSkills.isEmpty)
        XCTAssertEqual(detail.globalSkillsAvailability, .notApplicable)
    }

    /// The batch overload must agree with the per-Agent one for every Agent, so
    /// the faster path cannot silently change reported sizes.
    func testBatchStorageSizesMatchPerAgentResults() {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let codex = AIAgentEntry(
            id: "codex", displayName: "Codex", locality: .local,
            formFactors: [.cli], icon: .systemSymbol(name: "terminal"),
            dataRoots: [home.appending(path: ".codex")],
            configDirectories: [home.appending(path: ".config/codex")]
        )
        let claude = AIAgentEntry(
            id: "claude", displayName: "Claude", locality: .local,
            formFactors: [.cli], icon: .systemSymbol(name: "terminal"),
            dataRoots: [home.appending(path: ".claude")]
        )
        let items = [
            ScannedItem(
                url: home.appending(path: ".codex/sessions/a.jsonl"),
                logicalSize: 10, allocatedSize: 10,
                category: .conversation, risk: .safe, explanation: ""
            ),
            ScannedItem(
                url: home.appending(path: ".claude/projects/b.bin"),
                logicalSize: 20, allocatedSize: 20,
                category: .conversation, risk: .safe, explanation: ""
            ),
            ScannedItem(
                url: home.appending(path: "Documents/unrelated.pdf"),
                logicalSize: 40, allocatedSize: 40,
                category: .developer, risk: .safe, explanation: ""
            )
        ]
        let batch = AIAgentDetailProjection.storageSizes(items: items, forAgents: [codex, claude])
        for agent in [codex, claude] {
            let single = AIAgentDetailProjection.storageSizes(items: items, forAgent: agent)
            XCTAssertEqual(batch[agent.id] ?? [:], single, "batch must match per-agent for \(agent.id)")
        }
        // And unrelated items are attributed to nobody.
        let total = batch.values.flatMap(\.values).reduce(0, +)
        XCTAssertEqual(total, 30)
    }

    func testStorageSizesByCategoryAndBreakdownOrdering() {
        let home = URL(fileURLWithPath: "/Users/test")
        let codex = AIAgentEntry(
            id: "codex", displayName: "Codex", locality: .local,
            formFactors: [.cli], icon: .systemSymbol(name: "terminal"),
            dataRoots: [home.appending(path: ".codex")]
        )
        let items = [
            ScannedItem(
                url: home.appending(path: ".codex/sessions/a.jsonl"),
                logicalSize: 10, allocatedSize: 10,
                category: .conversation, risk: .safe, explanation: ""
            ),
            ScannedItem(
                url: home.appending(path: ".codex/logs/x.sqlite"),
                logicalSize: 50, allocatedSize: 50,
                category: .log, risk: .safe, explanation: ""
            ),
            ScannedItem(
                url: home.appending(path: ".codex/sessions/b.jsonl"),
                logicalSize: 5, allocatedSize: 5,
                category: .conversation, risk: .safe, explanation: ""
            ),
            // Outside every root — must not be attributed.
            ScannedItem(
                url: home.appending(path: "Documents/z.pdf"),
                logicalSize: 99, allocatedSize: 99,
                category: .developer, risk: .safe, explanation: ""
            )
        ]

        let byCategory = AIAgentDetailProjection.storageSizesByCategory(items: items, forAgents: [codex])
        XCTAssertEqual(byCategory["codex"]?[.conversation], 15)
        XCTAssertEqual(byCategory["codex"]?[.log], 50)
        XCTAssertNil(byCategory["codex"]?[.developer])

        // Breakdown is ordered largest-first and drops zero categories.
        let detail = AIAgentDetailProjection(
            agent: codex, skills: [], plugins: [],
            storageSizesByCategory: byCategory["codex"] ?? [:]
        )
        XCTAssertEqual(detail.storageBreakdown.map(\.category), [.log, .conversation])
        XCTAssertEqual(detail.storageBreakdown.map(\.allocatedSize), [50, 15])
    }

    func testRemoteAgentHasNoStorageBreakdown() {
        let remote = AIAgentEntry(
            id: "traex", displayName: "Traex", locality: .remote,
            formFactors: [.cloud], icon: .systemSymbol(name: "cloud")
        )
        let detail = AIAgentDetailProjection(
            agent: remote, skills: [], plugins: [],
            storageSizesByCategory: [.conversation: 100]
        )
        XCTAssertTrue(detail.storageBreakdown.isEmpty)
    }

    // MARK: - Temp-home fixtures (real filesystem, bounded)

    /// Builds a SKILL.md-bearing skill folder under `root`.
    private func makeSkill(at root: URL, named name: String) throws {
        let folder = root.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("---\nname: \(name)\ndescription: test\n---\n".utf8)
            .write(to: folder.appending(path: "SKILL.md"))
    }

    func testCodexClaudeTraeLocalSkillsAreDiscoveredAndAttributed() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "spacepilot-6a-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }

        try makeSkill(at: home.appending(path: ".codex/skills", directoryHint: .isDirectory), named: "codex-skill")
        try makeSkill(at: home.appending(path: ".codex/skills/.system", directoryHint: .isDirectory), named: "codex-system")
        try makeSkill(at: home.appending(path: ".claude/skills", directoryHint: .isDirectory), named: "claude-skill")
        try makeSkill(at: home.appending(path: ".trae/skills", directoryHint: .isDirectory), named: "trae-skill")
        // Trae CN builtin skills must attribute to Trae CN, not Global/shared.
        try makeSkill(at: home.appending(path: ".trae-cn/builtin_skills", directoryHint: .isDirectory), named: "trae-cn-builtin")
        // A genuinely shared skill.
        try makeSkill(at: home.appending(path: ".agents/skills", directoryHint: .isDirectory), named: "shared-skill")

        let roots = SkillRoot.production(homeDirectory: home)
        let records = try await SkillScanner().scan(roots: roots)

        func owner(ofSkillNamed name: String) -> AIAssetOwner? {
            records.first { $0.name == name }?.owner
        }
        XCTAssertEqual(owner(ofSkillNamed: "codex-skill"), .tool(definitionID: "codex"))
        XCTAssertEqual(owner(ofSkillNamed: "codex-system"), .tool(definitionID: "codex"))
        XCTAssertEqual(owner(ofSkillNamed: "claude-skill"), .tool(definitionID: "claude"))
        XCTAssertEqual(owner(ofSkillNamed: "trae-skill"), .tool(definitionID: "trae-cn"))
        XCTAssertEqual(owner(ofSkillNamed: "trae-cn-builtin"), .tool(definitionID: "trae-cn"))
        // Builtin skills must NOT be shared.
        XCTAssertNotEqual(owner(ofSkillNamed: "trae-cn-builtin"), .shared)
        XCTAssertEqual(owner(ofSkillNamed: "shared-skill"), .shared)
    }

    func testTraeCNSystemSkillLocationScopeIsNotUserGlobalShared() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "spacepilot-6a-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: home) }

        try makeSkill(at: home.appending(path: ".trae-cn/builtin_skills", directoryHint: .isDirectory), named: "trae-cn-builtin")
        let roots = SkillRoot.production(homeDirectory: home)
        let records = try await SkillScanner().scan(roots: roots)
        let record = try XCTUnwrap(records.first { $0.name == "trae-cn-builtin" })
        if case .tool(let id) = record.owner {
            XCTAssertEqual(id, "trae-cn")
        } else {
            XCTFail("Trae CN builtin skill should be tool-owned, got \(record.owner)")
        }
    }

    // MARK: - 6B: closing 6A observations

    /// An application-only definition (e.g. `chatgpt`) that is somehow seen only
    /// through CLI evidence must NOT advertise the undeclared `.cli` form factor.
    /// The intersection is strict: an empty intersection rejects the entry
    /// entirely rather than surfacing a formless Agent or falling back to the raw
    /// detected set.
    func testFormFactorsAreStrictIntersectionNoUndeclaredFallback() {
        let exeURL = URL(fileURLWithPath: "/usr/local/bin/chatgpt")
        let records = [
            toolRecord(kind: .cli, definitionID: "chatgpt", displayName: "ChatGPT",
                       evidence: AIToolEvidence(executableURL: exeURL), canonical: exeURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        // chatgpt declares only `.application`; seen only via a CLI executable the
        // strict intersection is empty, so NO Agent is produced (neither list) and
        // the undeclared `.cli` form factor is never surfaced.
        XCTAssertFalse(projection.localAgents.contains { $0.id == "chatgpt" })
        XCTAssertFalse(projection.remoteAgents.contains { $0.id == "chatgpt" })
        // And it must not leak into CLI Tools either (agent-capable definition).
        XCTAssertFalse(projection.cliTools.contains { $0.displayName == "ChatGPT" })
    }

    /// An application-only definition seen through its real app bundle keeps the
    /// single declared `.application` form factor and honestly shows nothing else.
    func testApplicationOnlyDefinitionKeepsSingleDeclaredFormFactor() {
        let appURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let records = [
            toolRecord(kind: .application, definitionID: "chatgpt", displayName: "ChatGPT",
                       evidence: AIToolEvidence(applicationURL: appURL), canonical: appURL.path),
            // A stray CLI record for the same definition must not add `.cli`.
            toolRecord(kind: .cli, definitionID: "chatgpt", displayName: "ChatGPT",
                       evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: "/usr/local/bin/chatgpt")),
                       canonical: "/usr/local/bin/chatgpt")
        ]
        let projection = AIAgentProjection(records: records)
        let chatgpt = projection.localAgents.first { $0.id == "chatgpt" }
        XCTAssertEqual(chatgpt?.formFactors, [.application])
    }

    /// Agent-capable CLIs (Aiden/Traex/Codex/Claude/Gemini/Aider) must never leak
    /// into the CLI Tools data source; supporting CLIs stay. Each agent appears
    /// exactly once (in its Agent list, not duplicated in CLI Tools).
    func testAgentCapableCLIsAreExcludedFromCLIToolsButSupportingCLIsStay() {
        func cli(_ id: String, _ name: String, _ path: String) -> AIToolRecord {
            toolRecord(kind: .cli, definitionID: id, displayName: name,
                       evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: path)), canonical: path)
        }
        let records = [
            cli("aiden", "Aiden", "/Users/x/Library/pnpm/bin/aiden"),
            cli("traex", "Traex", "/Users/x/.local/share/traex/current/traex"),
            cli("codex", "Codex", "/usr/local/bin/codex"),
            cli("claude", "Claude", "/usr/local/bin/claude"),
            cli("gemini-cli", "Gemini CLI", "/usr/local/bin/gemini"),
            cli("aider", "Aider", "/Users/x/.local/bin/aider"),
            cli("lark-cli", "Lark CLI", "/opt/homebrew/bin/lark-cli"),
            cli("bytedcli", "bytedcli", "/opt/homebrew/bin/bytedcli")
        ]
        let projection = AIAgentProjection(records: records)

        let cliToolNames = Set(projection.cliTools.map(\.displayName))
        for agentCLI in ["Aiden", "Traex", "Codex", "Claude", "Gemini CLI", "Aider"] {
            XCTAssertFalse(cliToolNames.contains(agentCLI), "\(agentCLI) must not appear in CLI Tools")
        }
        // Supporting CLIs remain in CLI Tools.
        XCTAssertTrue(cliToolNames.contains("Lark CLI"))
        XCTAssertTrue(cliToolNames.contains("bytedcli"))

        // Aiden / Traex each appear exactly once, in their respective Agent list.
        XCTAssertEqual(projection.localAgents.filter { $0.id == "aiden" }.count, 1)
        XCTAssertEqual(projection.remoteAgents.filter { $0.id == "traex" }.count, 1)
        XCTAssertFalse(projection.cliTools.contains { $0.owner == .tool(definitionID: "aiden") })
        XCTAssertFalse(projection.cliTools.contains { $0.owner == .tool(definitionID: "traex") })
    }

    /// ChatGPT and Codex must not both claim the same application bundle: on this
    /// machine `/Applications/ChatGPT.app` carries `com.openai.codex`, so the
    /// `chatgpt` definition owns that bundle and `codex` claims no bundle at all.
    func testChatGPTAndCodexDoNotBothClaimSameBundle() {
        let defs = KnownAIToolDefinitions.all
        let chatgpt = defs.first { $0.id == "chatgpt" }
        let codex = defs.first { $0.id == "codex" }
        XCTAssertEqual(chatgpt?.applicationBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(codex?.applicationBundleIdentifiers, [])
        // No two definitions may declare the same bundle identifier.
        var seen: [String: String] = [:]
        for def in defs {
            for bundle in def.applicationBundleIdentifiers {
                if let owner = seen[bundle] {
                    XCTFail("Bundle \(bundle) claimed by both \(owner) and \(def.id)")
                }
                seen[bundle] = def.id
            }
        }
    }

    /// Continue / Cline / Roo are VS Code extensions: they must NOT carry an
    /// agent profile and never appear as standalone Agents even with a data
    /// footprint. They surface only as VS Code host evidence.
    func testVSCodeExtensionsAreNotStandaloneAgents() {
        let defs = KnownAIToolDefinitions.all
        for id in ["continue", "cline", "roo"] {
            let def = defs.first { $0.id == id }
            XCTAssertNotNil(def, "\(id) definition should still exist for host evidence")
            XCTAssertNil(def?.agentProfile, "\(id) must not be a standalone Agent")
        }
        // Even given (hypothetical) executable evidence, no Agent is produced,
        // because the definition carries no agent profile.
        let records = [
            toolRecord(kind: .cli, definitionID: "continue", displayName: "Continue",
                       evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: "/usr/local/bin/continue")),
                       canonical: "/usr/local/bin/continue")
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertFalse(projection.localAgents.contains { $0.id == "continue" })
        XCTAssertFalse(projection.remoteAgents.contains { $0.id == "continue" })
    }

    /// Warp is permanently excluded (not an AI Agent). OpenCode without real
    /// app/CLI evidence must not surface as an Agent.
    func testWarpExcludedAndOpenCodeConfigOnlyDoesNotSurface() {
        let defs = KnownAIToolDefinitions.all
        XCTAssertNil(defs.first { $0.id == "warp" }, "Warp must not be a known definition")

        // OpenCode with only a config/data footprint (skill record, no executable)
        // must not fabricate an Agent.
        let cfgURL = URL(fileURLWithPath: "/Users/x/.config/opencode/config.json")
        let records = [
            toolRecord(kind: .skill, definitionID: "opencode", displayName: "OpenCode",
                       evidence: AIToolEvidence(skillRoots: [cfgURL]), canonical: cfgURL.path)
        ]
        let projection = AIAgentProjection(records: records)
        XCTAssertFalse(projection.localAgents.contains { $0.id == "opencode" })
        XCTAssertFalse(projection.remoteAgents.contains { $0.id == "opencode" })
    }
}
