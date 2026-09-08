import XCTest
@testable import SpacePilotCore

/// Verifies the capability scanner against the *real* config files on this
/// machine. These are integration checks: they assert the scanner's behaviour
/// where a file exists, and skip cleanly where it does not, so the suite stays
/// green on a machine with a different set of Agents installed.
final class AICapabilityScannerTests: XCTestCase {
    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }

    /// The parser must find the MCP servers actually declared in Codex's TOML,
    /// including the ones marked `enabled = false` (a disabled server is still
    /// installed, and hiding it would misreport what is on disk).
    func testCodexTOMLYieldsDeclaredMCPServersIncludingDisabled() throws {
        let config = home.appending(path: ".codex/config.toml")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: config.path))

        let result = AICapabilityScanner().scan(homeDirectory: home)
        let codex = result.mcpServers.filter { $0.ownerDefinitionID == "codex" }
        XCTAssertFalse(codex.isEmpty, "Codex declares MCP servers; scanner found none")

        // Every record must point back at the file it came from.
        XCTAssertTrue(codex.allSatisfy { $0.sourceURL.path == config.path })
        // Names must be bare server names, never TOML header fragments.
        XCTAssertFalse(codex.contains { $0.name.contains("mcp_servers") || $0.name.contains(".") })
        // `[mcp_servers.node_repl.env]` is a sub-table and must not become a server.
        XCTAssertEqual(Set(codex.map(\.name)).count, codex.count, "duplicate server rows")
    }

    /// Claude stores hooks in `settings.json`; each event must report the real
    /// number of attached handlers, flattening the matcher-group shape.
    func testClaudeSettingsYieldHooksWithHandlerCounts() throws {
        let settings = home.appending(path: ".claude/settings.json")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: settings.path))

        let result = AICapabilityScanner().scan(homeDirectory: home)
        let hooks = result.hooks.filter { $0.ownerDefinitionID == "claude" }
        XCTAssertFalse(hooks.isEmpty, "Claude declares hooks; scanner found none")
        // A discovered event with zero handlers would mean the flattening failed.
        XCTAssertTrue(hooks.allSatisfy { $0.handlerCount > 0 })
        XCTAssertEqual(Set(hooks.map(\.event)).count, hooks.count, "duplicate event rows")
    }

    /// `~/.codex/AGENTS.md` is the global instruction file and must be surfaced
    /// with the size and line count currently present on disk. An empty but
    /// valid instruction file is still a discovered capability.
    func testGlobalInstructionFileIsSurfacedWithSizeAndLines() throws {
        let agents = home.appending(path: ".codex/AGENTS.md")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: agents.path))

        let result = AICapabilityScanner().scan(homeDirectory: home)
        let file = try XCTUnwrap(result.instructionFiles.first { $0.url.path == agents.path })
        let contents = try String(contentsOf: agents, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: agents.path)
        XCTAssertEqual(file.ownerDefinitionID, "codex")
        XCTAssertEqual(file.allocatedSize, (attributes[.size] as? NSNumber)?.int64Value)
        XCTAssertEqual(
            file.lineCount,
            contents.split(separator: "\n", omittingEmptySubsequences: false).count
        )
    }

    /// A missing home must produce empty results and no failures — "nothing
    /// installed" is a normal state, not an error.
    func testAbsentConfigsProduceEmptyResultWithoutFailures() {
        let empty = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotEmptyHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        let result = AICapabilityScanner().scan(homeDirectory: empty)
        XCTAssertTrue(result.mcpServers.isEmpty)
        XCTAssertTrue(result.hooks.isEmpty)
        XCTAssertTrue(result.instructionFiles.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
    }

    /// A file that exists but is not valid JSON must be reported as a failure,
    /// not silently treated as "no hooks/servers".
    func testUnparsableConfigIsReportedAsFailureNotSilence() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotBadHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        let claudeDir = root.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let settings = claudeDir.appending(path: "settings.json")
        try "{ this is not json".write(to: settings, atomically: true, encoding: .utf8)

        let result = AICapabilityScanner().scan(homeDirectory: root)
        XCTAssertEqual(result.failures[settings.path], .invalidOutput)
        XCTAssertTrue(result.hooks.isEmpty)
    }

    // MARK: - Config profile extraction

    func testCodexTOMLConfigProfileReadsModelEffortAndCredentialPresence() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotCfgHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        let codexDir = root.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = codexDir.appending(path: "config.toml")
        try """
        model = "gpt-5.6-sol"
        model_reasoning_effort = "high"

        [mcp_servers.node_repl]
        command = "node"
        model = "should-be-ignored-inside-table"
        """.write(to: config, atomically: true, encoding: .utf8)
        // Sibling auth.json signals a credential is configured (never read).
        try "{}".write(to: codexDir.appending(path: "auth.json"), atomically: true, encoding: .utf8)

        let result = AICapabilityScanner().scan(homeDirectory: root)
        let profile = try XCTUnwrap(result.configProfiles.first { $0.ownerDefinitionID == "codex" })
        XCTAssertEqual(profile.model, "gpt-5.6-sol")
        XCTAssertEqual(profile.reasoningEffort, "high")
        XCTAssertTrue(profile.hasCredential)
    }

    func testCodexTOMLWithoutCredentialFileReportsNoCredential() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotCfgHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        let codexDir = root.appending(path: ".codex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "model = \"gpt-5\"\n".write(to: codexDir.appending(path: "config.toml"), atomically: true, encoding: .utf8)

        let result = AICapabilityScanner().scan(homeDirectory: root)
        let profile = try XCTUnwrap(result.configProfiles.first { $0.ownerDefinitionID == "codex" })
        XCTAssertEqual(profile.model, "gpt-5")
        XCTAssertNil(profile.reasoningEffort)
        XCTAssertFalse(profile.hasCredential)
    }

    func testClaudeSettingsConfigProfileReadsModelAndCredentialFromEnvToken() throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotCfgHome-\(UUID().uuidString)", directoryHint: .isDirectory)
        let claudeDir = root.appending(path: ".claude", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        { "model": "claude-sonnet-4", "env": { "ANTHROPIC_AUTH_TOKEN": "secret-never-read" } }
        """.write(to: claudeDir.appending(path: "settings.json"), atomically: true, encoding: .utf8)

        let result = AICapabilityScanner().scan(homeDirectory: root)
        let profile = try XCTUnwrap(result.configProfiles.first { $0.ownerDefinitionID == "claude" })
        XCTAssertEqual(profile.model, "claude-sonnet-4")
        XCTAssertTrue(profile.hasCredential)
        // The secret value must never be captured anywhere on the record.
        XCTAssertFalse("\(profile)".contains("secret-never-read"))
    }

    /// Record IDs must be stable across runs so re-scanning an unchanged machine
    /// does not churn the snapshot.
    func testRecordIDsAreStableAcrossRepeatedScans() {
        let scanner = AICapabilityScanner()
        let first = scanner.scan(homeDirectory: home)
        let second = scanner.scan(homeDirectory: home)
        XCTAssertEqual(first.mcpServers.map(\.id), second.mcpServers.map(\.id))
        XCTAssertEqual(first.hooks.map(\.id), second.hooks.map(\.id))
        XCTAssertEqual(first.instructionFiles.map(\.id), second.instructionFiles.map(\.id))
    }

    // MARK: - Markdown outline parsing

    func testMarkdownOutlineExtractsFirstH1AndAllH2InOrder() {
        let doc = """
        # Codex Global Instructions

        Some intro text.

        ## Language
        使用中文。

        ## Environment & Dependencies
        details

        ### A sub-heading is not a section
        ## Execution & Verification
        """
        let outline = AICapabilityScanner.markdownOutline(
            lines: doc.split(separator: "\n", omittingEmptySubsequences: false)
        )
        XCTAssertEqual(outline.title, "Codex Global Instructions")
        XCTAssertEqual(outline.sections, ["Language", "Environment & Dependencies", "Execution & Verification"])
    }

    func testMarkdownOutlineIgnoresHeadingsInsideCodeFences() {
        let doc = """
        # Title

        ```
        # not a title
        ## not a section
        ```

        ## Real Section
        """
        let outline = AICapabilityScanner.markdownOutline(
            lines: doc.split(separator: "\n", omittingEmptySubsequences: false)
        )
        XCTAssertEqual(outline.title, "Title")
        XCTAssertEqual(outline.sections, ["Real Section"])
    }

    func testMarkdownOutlineHandlesNoHeadings() {
        let outline = AICapabilityScanner.markdownOutline(
            lines: "just prose\nmore prose".split(separator: "\n", omittingEmptySubsequences: false)
        )
        XCTAssertNil(outline.title)
        XCTAssertTrue(outline.sections.isEmpty)
    }
}
