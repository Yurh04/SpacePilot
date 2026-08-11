import XCTest
@testable import SpacePilotCore

final class AIToolRegistryTests: XCTestCase {

    // MARK: - Test doubles

    private struct StubApplicationLocator: AIApplicationLocating {
        let installed: [String: URL]
        func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
            installed[bundleIdentifier]
        }
    }

    /// Directory probe keyed by canonical (symlink-resolved) path so tests can
    /// model presence, absence, and permission failures deterministically.
    private struct StubDirectoryProbe: AIDirectoryProbing {
        let results: [String: AIDirectoryProbeResult]
        func probeDirectory(at url: URL) -> AIDirectoryProbeResult {
            let key = AIToolRegistry.canonicalKey(url)
            return results[key] ?? .missing
        }
    }

    private struct StubCLIRunner: CLIProcessRunning {
        func run(
            executableURL: URL,
            arguments: [String],
            environment: [String: String],
            timeout: Duration,
            maximumOutputBytes: Int
        ) async throws -> CLIProcessOutput {
            CLIProcessOutput(
                standardOutput: Data(),
                standardError: Data(),
                terminationStatus: 0,
                didTimeout: false,
                outputTruncated: false
            )
        }
    }

    private struct NeverExecutableLocator: ExecutableLocating {
        func isExecutableFile(at url: URL) -> Bool { false }
    }

    private func makeCLIProbe() -> SafeCLIVersionProbe {
        SafeCLIVersionProbe(
            runner: StubCLIRunner(),
            locator: NeverExecutableLocator()
        )
    }

    private func canonical(_ home: URL, _ relative: String) -> String {
        AIToolRegistry.canonicalKey(
            home.appending(path: relative, directoryHint: .isDirectory)
        )
    }

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Creates the fixed npm package directory that the FNM candidate gate now
    /// requires (`installation/lib/node_modules/<packageID>`), so the version
    /// root counts as having installed the tool.
    private func makeInstalledFNMPackage(
        home: URL,
        version: String,
        packageIdentifier: String
    ) throws {
        var packageURL = home
            .appending(path: ".local/share/fnm/node-versions/\(version)/installation/lib/node_modules", directoryHint: .isDirectory)
        for component in packageIdentifier.split(separator: "/", omittingEmptySubsequences: true) {
            packageURL = packageURL.appending(path: String(component), directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
    }

    // MARK: - Hit / miss

    func testKnownDefinitionsCoverRequired4BToolsWithStableIDs() {
        let definitions = KnownAIToolDefinitions.all
        let ids = definitions.map(\.id)

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0 == $0.lowercased() })
        XCTAssertEqual(definitions.first { $0.id == "trae-cn" }?.applicationBundleIdentifiers, ["cn.trae.app"])
        XCTAssertEqual(definitions.first { $0.id == "trae-solo-cn" }?.applicationBundleIdentifiers, ["cn.trae.solo.app"])
        XCTAssertEqual(definitions.first { $0.id == "antigravity" }?.applicationBundleIdentifiers, ["com.google.antigravity"])
        XCTAssertEqual(definitions.first { $0.id == "vscode" }?.applicationBundleIdentifiers, ["com.microsoft.VSCode"])
        XCTAssertEqual(definitions.first { $0.id == "aiden" }?.cliProbeID, "aiden")
        // ChatGPT desktop app uses the `com.openai.codex` bundle ID; the codex
        // definition is a CLI/npm tool and must not claim any app bundle.
        XCTAssertEqual(definitions.first { $0.id == "chatgpt" }?.applicationBundleIdentifiers, ["com.openai.codex"])
        XCTAssertEqual(definitions.first { $0.id == "codex" }?.applicationBundleIdentifiers, [])
        // Newly-added, bundle-verified AI applications.
        XCTAssertEqual(definitions.first { $0.id == "aime" }?.applicationBundleIdentifiers, ["com.bytedance.aime.electron"])
        XCTAssertEqual(definitions.first { $0.id == "mira" }?.applicationBundleIdentifiers, ["net.byteintl.mira"])
        XCTAssertEqual(definitions.first { $0.id == "doubao" }?.applicationBundleIdentifiers, ["com.bot.pc.doubao"])
        XCTAssertEqual(definitions.first { $0.id == "cici" }?.applicationBundleIdentifiers, ["com.bot.pc.cici"])
        XCTAssertEqual(definitions.first { $0.id == "m365-copilot" }?.applicationBundleIdentifiers, ["com.microsoft.m365copilot.shim"])
        // Warp was removed as an AI application per the user's ruling: it is a
        // terminal, not an AI Agent, and must no longer appear in the catalog.
        XCTAssertNil(definitions.first { $0.id == "warp" })
        for required in [
            "codex", "claude", "chatgpt", "cursor", "windsurf", "gemini-cli",
            "opencode", "aider", "copilot", "continue", "cline", "roo",
            "ollama", "lm-studio", "jan"
        ] {
            XCTAssertTrue(ids.contains(required), "Missing existing definition: \(required)")
        }
        // Newly-added, machine-confirmed CLI-only tools resolved through fixed,
        // code-owned probe templates (FNM, uv tool root, Homebrew, or an exact
        // home-relative install path). Each references a whitelisted probe ID.
        for (definitionID, probeID) in [
            ("merlin-cli", "merlin-cli"),
            ("one-cli", "one"),
            ("bytedcli", "bytedcli"),
            ("opencli", "opencli"),
            ("botmux", "botmux"),
            ("traex", "traex"),
            ("lark-cli", "lark-cli"),
            ("aime", "aime"),
            ("mira", "mira")
        ] {
            let definition = definitions.first { $0.id == definitionID }
            XCTAssertEqual(definition?.cliProbeID, probeID, "Missing CLI probe for \(definitionID)")
            XCTAssertTrue(
                SafeCLIVersionProbe.isKnownProbe(probeID),
                "Probe \(probeID) is not whitelisted"
            )
        }
    }

    func testDiscoversApplicationWhenBundleInstalled() async throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            applicationBundleIdentifiers: ["com.openai.codex"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(
                installed: ["com.openai.codex": URL(filePath: "/Applications/Codex.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.kind, .application)
        XCTAssertEqual(record.owner, .tool(definitionID: "codex"))
        XCTAssertEqual(record.evidence.applicationURL, URL(filePath: "/Applications/Codex.app"))
    }

    func testOmitsToolWithNoEvidence() async throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "chatgpt",
            displayName: "ChatGPT",
            applicationBundleIdentifiers: ["com.openai.chat"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        XCTAssertTrue(records.isEmpty)
    }

    func testDoesNotFalselyReportUnrelatedBundle() async throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "cursor",
            displayName: "Cursor",
            applicationBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(
                installed: ["com.some.other.app": URL(filePath: "/Applications/Other.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        XCTAssertTrue(records.isEmpty)
    }

    func testVSCodeBundleAloneDoesNotEnterAIManagementWithoutFixedAIEvidence() async throws {
        let home = URL(filePath: "/Users/test")
        let vscode = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == "vscode" })
        let registry = AIToolRegistry(
            definitions: [vscode],
            applicationLocator: StubApplicationLocator(
                installed: ["com.microsoft.VSCode": URL(filePath: "/Applications/Visual Studio Code.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".vscode/extensions"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        XCTAssertTrue(records.isEmpty)
    }

    func testVSCodeEntersAIManagementOnlyWithFixedExtensionOrConfigEvidence() async throws {
        let home = URL(filePath: "/Users/test")
        let vscode = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == "vscode" })
        let copilotStorage = "Library/Application Support/Code/User/globalStorage/github.copilot-chat"
        let registry = AIToolRegistry(
            definitions: [vscode],
            applicationLocator: StubApplicationLocator(
                installed: ["com.microsoft.VSCode": URL(filePath: "/Applications/Visual Studio Code.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, copilotStorage): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.owner, .tool(definitionID: "vscode"))
        XCTAssertEqual(record.evidence.bundleIdentifier, "com.microsoft.VSCode")
        XCTAssertEqual(record.evidence.configDirectories.map { AIToolRegistry.canonicalKey($0) }, [canonical(home, copilotStorage)])
    }

    func testRealInstalledCLILayoutsProduceNonEmptyAIManagementProjectionCLIs() async throws {
        let tree = try TemporaryTree(files: [:])
        try makeExecutable(at: tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/codex",
            directoryHint: .notDirectory
        ))
        try makeExecutable(at: tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/claude",
            directoryHint: .notDirectory
        ))
        try makeInstalledFNMPackage(home: tree.url, version: "v24.18.0", packageIdentifier: "@openai/codex")
        try makeInstalledFNMPackage(home: tree.url, version: "v24.18.0", packageIdentifier: "@anthropic-ai/claude-code")
        try makeExecutable(at: tree.url.appending(
            path: "Library/pnpm/bin/aiden",
            directoryHint: .notDirectory
        ))
        let definitions = KnownAIToolDefinitions.all.filter { ["codex", "claude", "aiden"].contains($0.id) }
        let registry = AIToolRegistry(
            definitions: definitions,
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: SafeCLIVersionProbe(
                runner: StubCLIRunner(),
                locator: LocalExecutableLocator()
            )
        )

        let projection = AIManagementProjection(records: try await registry.discover(homeDirectory: tree.url))

        XCTAssertEqual(Set(projection.clis.map(\.owner)), [
            .tool(definitionID: "aiden"),
            .tool(definitionID: "claude"),
            .tool(definitionID: "codex")
        ])
        XCTAssertEqual(projection.clis.count, 3)
        XCTAssertTrue(projection.clis.allSatisfy { $0.evidence.executableURL != nil })
        XCTAssertTrue(projection.clis.allSatisfy { $0.coverageFailures.contains(.invalidOutput) })
    }

    func testExpandedCLILayoutsProduceOwnerRecordsForMerlinTraexAndUvTool() async throws {
        let tree = try TemporaryTree(files: [:])
        // merlin-cli: exact home-relative install path.
        try makeExecutable(at: tree.url.appending(
            path: ".merlin-cli/bin/merlin-cli",
            directoryHint: .notDirectory
        ))
        // traex: ~/.local/share/traex/current -> releases/<version>/traex.
        let traexRelease = tree.url.appending(
            path: ".local/share/traex/releases/0.200.19/traex",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: traexRelease)
        try FileManager.default.createSymbolicLink(
            at: tree.url.appending(path: ".local/share/traex/current", directoryHint: .isDirectory),
            withDestinationURL: tree.url.appending(path: ".local/share/traex/releases/0.200.19", directoryHint: .isDirectory)
        )
        // traex aliases resolve to the same executable and must surface as evidence.
        let traexPrimary = tree.url.appending(path: ".local/share/traex/current/traex", directoryHint: .notDirectory)
        let localBin = tree.url.appending(path: ".local/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        for alias in ["trae-cli", "trae-agent"] {
            try FileManager.default.createSymbolicLink(
                at: localBin.appending(path: alias, directoryHint: .notDirectory),
                withDestinationURL: traexPrimary
            )
        }
        // mira: fixed uv tool root.
        try makeExecutable(at: tree.url.appending(
            path: ".local/share/uv/tools/togo-cli/bin/mira",
            directoryHint: .notDirectory
        ))
        let definitions = KnownAIToolDefinitions.all.filter { ["merlin-cli", "traex", "mira"].contains($0.id) }
        let registry = AIToolRegistry(
            definitions: definitions,
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: SafeCLIVersionProbe(
                runner: StubCLIRunner(),
                locator: LocalExecutableLocator()
            )
        )

        let projection = AIManagementProjection(records: try await registry.discover(homeDirectory: tree.url))

        XCTAssertEqual(Set(projection.clis.map(\.owner)), [
            .tool(definitionID: "merlin-cli"),
            .tool(definitionID: "traex"),
            .tool(definitionID: "mira")
        ])
        XCTAssertTrue(projection.clis.allSatisfy { $0.evidence.executableURL != nil })

        let traex = try XCTUnwrap(projection.clis.first { $0.owner == .tool(definitionID: "traex") })
        XCTAssertEqual(
            traex.evidence.aliasExecutableURLs.map(\.lastPathComponent),
            ["trae-agent", "trae-cli"]
        )
    }

    // MARK: - Coverage failure retention

    func testPermissionDeniedDataRootDoesNotFabricateApplicationForCLIOnlyTool() async throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "aider",
            displayName: "Aider",
            dataRootRelativePaths: [".aider"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".aider"): .failure(.permissionDenied)
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        // Aider has no application bundle identifier, so a data-root footprint
        // (even an unreadable one) must never fabricate an application record.
        XCTAssertTrue(records.filter { $0.kind == .application }.isEmpty)
    }

    func testConfigOnlyFootprintDoesNotFabricateApplicationWhenBundleAbsent() async throws {
        let home = URL(filePath: "/Users/test")
        let cursor = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == "cursor" })
        let opencode = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == "opencode" })
        let registry = AIToolRegistry(
            definitions: [cursor, opencode],
            // No Cursor app installed, and OpenCode has no bundle at all.
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".cursor"): .present,
                canonical(home, ".config/opencode"): .present,
                canonical(home, ".opencode"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        // A leftover `~/.cursor` or `~/.config/opencode` must not appear as an
        // installed AI application.
        XCTAssertTrue(records.filter { $0.kind == .application }.isEmpty)
    }

    func testInstalledBundleWithConfigFootprintProducesApplicationWithConfigEvidence() async throws {
        let home = URL(filePath: "/Users/test")
        let cursor = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == "cursor" })
        let registry = AIToolRegistry(
            definitions: [cursor],
            applicationLocator: StubApplicationLocator(
                installed: ["com.todesktop.230313mzl4w4u92": URL(filePath: "/Applications/Cursor.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".cursor"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        let app = try XCTUnwrap(records.first { $0.kind == .application })
        XCTAssertEqual(app.owner, .tool(definitionID: "cursor"))
        XCTAssertEqual(app.evidence.applicationURL, URL(filePath: "/Applications/Cursor.app"))
        // The config footprint attaches to the installed app as evidence.
        XCTAssertEqual(
            app.evidence.configDirectories.map { AIToolRegistry.canonicalKey($0) },
            [canonical(home, ".cursor")]
        )
    }

    // MARK: - Shared skill ownership + dedup

    func testSharedSkillRootCollapsesAcrossToolsIntoSingleSharedRecord() async throws {
        let home = URL(filePath: "/Users/test")
        let shared = AIToolRootDescriptor(
            ".agents/skills",
            ownership: .shared,
            displayNameOverride: "Shared Agent Skills"
        )
        let codex = AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            skillRoots: [AIToolRootDescriptor(".codex/skills"), shared]
        )
        let claude = AIToolDefinition(
            id: "claude",
            displayName: "Claude",
            skillRoots: [AIToolRootDescriptor(".claude/skills"), shared]
        )
        let registry = AIToolRegistry(
            definitions: [codex, claude],
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".codex/skills"): .present,
                canonical(home, ".claude/skills"): .present,
                canonical(home, ".agents/skills"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        let skillRecords = records.filter { $0.kind == .skill }
        // Two tool-specific roots plus exactly one shared root.
        XCTAssertEqual(skillRecords.count, 3)
        let sharedRecords = skillRecords.filter { $0.owner == .shared }
        XCTAssertEqual(sharedRecords.count, 1)
        XCTAssertEqual(sharedRecords.first?.displayName, "Shared Agent Skills")
    }

    // MARK: - Canonical directory overlap dedup

    func testOverlappingCanonicalDataRootsDeduplicate() async throws {
        let home = URL(filePath: "/Users/test")
        // Two relative paths that canonicalize to the same location. Data roots
        // no longer fabricate applications on their own, so anchor the dedup
        // assertion on a real installed-app fixture where the overlapping data
        // roots attach as evidence.
        let definition = AIToolDefinition(
            id: "claude",
            displayName: "Claude",
            applicationBundleIdentifiers: ["com.anthropic.claudefordesktop"],
            dataRootRelativePaths: [".claude", "./.claude"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(
                installed: ["com.anthropic.claudefordesktop": URL(filePath: "/Applications/Claude.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".claude"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        let record = try XCTUnwrap(records.first { $0.kind == .application })
        XCTAssertEqual(record.evidence.dataRoots.count, 1)
    }

    // MARK: - Stable IDs

    func testStableIDIsDeterministicAcrossRuns() async throws {
        let home = URL(filePath: "/Users/test")
        let definition = AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            applicationBundleIdentifiers: ["com.openai.codex"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(
                installed: ["com.openai.codex": URL(filePath: "/Applications/Codex.app")]
            ),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: makeCLIProbe()
        )

        let first = try await registry.discover(homeDirectory: home)
        let second = try await registry.discover(homeDirectory: home)

        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertFalse(first.isEmpty)
        // No random UUIDs: the ID encodes kind, owner and canonical location.
        XCTAssertEqual(
            first.first?.id,
            "application:codex:/Applications/Codex.app"
        )
    }

    // MARK: - Cancellation propagation

    func testCancellationStopsDiscoveryAndThrows() async throws {
        let home = URL(filePath: "/Users/test")
        let definitions = (0..<50).map {
            AIToolDefinition(
                id: "tool-\($0)",
                displayName: "Tool \($0)",
                applicationBundleIdentifiers: ["com.example.tool\($0)"]
            )
        }
        let registry = AIToolRegistry(
            definitions: definitions,
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [:]),
            cliProbe: makeCLIProbe()
        )

        let task = Task { try await registry.discover(homeDirectory: home) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected discovery to throw CancellationError")
        } catch is CancellationError {
            // Expected: cancellation is not masked as an empty result.
        }
    }
}
