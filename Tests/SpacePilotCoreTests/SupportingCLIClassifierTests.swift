import XCTest
@testable import SpacePilotCore

final class SupportingCLIClassifierTests: XCTestCase {

    private func cli(_ id: String, name: String, executable: String? = nil) -> AIToolRecord {
        AIToolRecord(
            id: "cli:\(id):/bin/\(id)",
            kind: .cli,
            displayName: name,
            owner: .tool(definitionID: id),
            evidence: AIToolEvidence(
                executableURL: executable.map { URL(fileURLWithPath: $0) }
            )
        )
    }

    private func mcp(_ name: String, owner: String = "codex") -> MCPServerRecord {
        MCPServerRecord(
            name: name,
            ownerDefinitionID: owner,
            sourceURL: URL(fileURLWithPath: "/Users/test/.codex/config.toml"),
            transport: .stdio,
            command: nil,
            isEnabled: true
        )
    }

    func testKeywordNamedToolIsReclassifiedButPeerCLIsStay() {
        let records = [
            cli("botmux", name: "botmux"),
            cli("one-cli", name: "One CLI"),
            cli("bytedcli", name: "Bytedcli"),
            cli("lark-cli", name: "Lark CLI")
        ]

        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: [])

        // botmux matches the `mux` capability keyword; the peer ByteDance CLIs,
        // which are structurally identical, must NOT be swept in.
        XCTAssertEqual(result.otherTools.map(\.displayName), ["botmux"])
        XCTAssertEqual(
            Set(result.commandLineTools.map(\.displayName)),
            ["One CLI", "Bytedcli", "Lark CLI"]
        )
    }

    func testMCPRegisteredToolIsReclassified() {
        let records = [
            cli("openviking", name: "openviking"),
            cli("lark-cli", name: "Lark CLI")
        ]
        // openviking is also registered as an MCP server against an Agent.
        let servers = [mcp("openviking")]

        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: servers)

        XCTAssertEqual(result.otherTools.map(\.displayName), ["openviking"])
        XCTAssertEqual(result.commandLineTools.map(\.displayName), ["Lark CLI"])
    }

    func testMCPNameMatchIgnoresSeparatorsAndCase() {
        let records = [cli("lark-cli", name: "Lark CLI")]
        // MCP server name spelled differently but normalizes to the same token.
        let servers = [mcp("LARKCLI")]

        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: servers)

        XCTAssertEqual(result.otherTools.map(\.displayName), ["Lark CLI"])
        XCTAssertTrue(result.commandLineTools.isEmpty)
    }

    func testPlainToolCLIsAreAllKeptAsCommandLineTools() {
        let records = [
            cli("one-cli", name: "One CLI"),
            cli("bytedcli", name: "Bytedcli"),
            cli("opencli", name: "OpenCLI"),
            cli("merlin-cli", name: "Merlin CLI")
        ]

        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: [])

        XCTAssertTrue(result.otherTools.isEmpty)
        XCTAssertEqual(result.commandLineTools.count, 4)
    }

    func testStandaloneListedToolsAreReclassifiedButPeersStay() {
        let records = [
            cli("devspace", name: "devspace"),
            cli("csj-proxy", name: "csjadk-proxy"),
            cli("lark-cli", name: "Lark CLI"),
            cli("bytedcli", name: "Bytedcli")
        ]

        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: [])

        // devspace and csj-proxy are on the code-owned standalone list even though
        // their names carry no capability keyword; structurally-identical peer
        // CLIs are not swept in.
        XCTAssertEqual(
            Set(result.otherTools.map(\.displayName)),
            ["devspace", "csjadk-proxy"]
        )
        XCTAssertEqual(
            Set(result.commandLineTools.map(\.displayName)),
            ["Lark CLI", "Bytedcli"]
        )
    }

    func testReclassifiedToolsFeedOtherAIToolsProjection() throws {
        let records = [cli("botmux", name: "botmux", executable: "/opt/homebrew/bin/botmux")]
        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: [])

        let tools = OtherAIToolProjection.tools(
            hooks: [],
            mcpServers: [],
            reclassifiedCLIs: result.otherTools
        )

        let botmux = try XCTUnwrap(tools.first { $0.name == "botmux" })
        XCTAssertEqual(botmux.kind, .packageInstalled)
        XCTAssertEqual(botmux.installMethod, .homebrew)
    }

    func testInherentMCPServerToolSurfacesAsMCPServerKind() throws {
        let records = [cli("devspace", name: "devspace", executable: "/Users/test/.local/bin/devspace")]
        let result = SupportingCLIClassifier.classify(cliRecords: records, mcpServers: [])

        // devspace reclassifies to an "other AI tool" and, being an MCP server by
        // nature, is labelled `.mcpServer` even though no Agent registers it.
        let tools = OtherAIToolProjection.tools(
            hooks: [],
            mcpServers: [],
            reclassifiedCLIs: result.otherTools
        )
        let devspace = try XCTUnwrap(tools.first { $0.name == "devspace" })
        XCTAssertEqual(devspace.kind, .mcpServer)
    }
}
