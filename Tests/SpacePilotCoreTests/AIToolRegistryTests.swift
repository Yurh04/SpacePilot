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
        for required in [
            "codex", "claude", "chatgpt", "cursor", "windsurf", "gemini-cli",
            "opencode", "aider", "copilot", "continue", "cline", "roo",
            "ollama", "lm-studio", "jan"
        ] {
            XCTAssertTrue(ids.contains(required), "Missing existing definition: \(required)")
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

    // MARK: - Coverage failure retention

    func testPermissionDeniedDataRootRetainedAsCoverageFailure() async throws {
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

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.kind, .application)
        XCTAssertTrue(record.coverageFailures.contains(.permissionDenied))
        // The data root was not readable, so no present data root is recorded.
        XCTAssertTrue(record.evidence.dataRoots.isEmpty)
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
        // Two relative paths that canonicalize to the same location.
        let definition = AIToolDefinition(
            id: "opencode",
            displayName: "OpenCode",
            dataRootRelativePaths: [".opencode", "./.opencode"]
        )
        let registry = AIToolRegistry(
            definitions: [definition],
            applicationLocator: StubApplicationLocator(installed: [:]),
            directoryProbe: StubDirectoryProbe(results: [
                canonical(home, ".opencode"): .present
            ]),
            cliProbe: makeCLIProbe()
        )

        let records = try await registry.discover(homeDirectory: home)

        let record = try XCTUnwrap(records.first)
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
