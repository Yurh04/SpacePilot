import XCTest
@testable import SpacePilotCore

final class AIWorkspaceUpdateTests: XCTestCase {
    private actor CaskFetcher: UpdateMetadataFetching {
        var requests: [UpdateMetadataRequest] = []
        func fetch(_ request: UpdateMetadataRequest) async throws -> UpdateMetadataResponse {
            requests.append(request)
            return .init(latestVersion: "1.105.0")
        }
    }

    func testCaskCheckPublishesAvailableWithoutExecutingAnything() async throws {
        let fetcher = CaskFetcher()
        let asset = AIUpdateAsset(key: .init(kind: .application, owner: .unknown, canonicalLocation: "/fixture/Code.app"), displayName: "Code", definitionID: "vscode",
            localVersion: .resolved(.init(version: "1.104.0", source: .applicationBundle, confidence: .high)),
            capability: ApplicationUpdateRoute.capability(bundleIdentifier: "com.microsoft.VSCode"))
        let results = await AIUpdateChecker(fetcher: fetcher).check([asset])
        XCTAssertEqual(results.first?.status, .updateAvailable)
        let requests = await fetcher.requests
        XCTAssertEqual(requests, [.homebrewCask(token: "visual-studio-code")])
        let plan = UpdateExecutionPlan(selectedKeys: [asset.key], assets: [asset], executionCapabilities: [:], results: Dictionary(uniqueKeysWithValues: results.map { ($0.assetKey, $0) }))
        XCTAssertFalse(plan.hasExecutable)
        XCTAssertEqual(plan.skipped.first?.reason, .checkOnly)
    }

    private func cli(_ id: String, path: String?) -> AIToolRecord {
        AIToolRecord(id: "cli:\(id)", kind: .cli, displayName: id, owner: .tool(definitionID: id),
                     evidence: AIToolEvidence(executableURL: path.map { URL(fileURLWithPath: $0) }, detectedVersion: "1.0.0"))
    }

    func testMissingExecutableRemainsSelectableAndExplicitlyUnsupported() throws {
        let record = cli("cis-cli", path: nil)
        let inventory = AIUpdateAssetBuilder.inventory(snapshot: nil, managementProjection: .init(records: [record]), projectSkills: [], projectPlugins: [])
        let asset = try XCTUnwrap(inventory.assets.first)
        XCTAssertEqual(asset.key, AIUpdateIdentity.cli(record))
        XCTAssertNil(asset.capability)
        XCTAssertTrue(inventory.executionCapabilities.isEmpty)
        XCTAssertEqual(inventory.unsupportedResults.first?.assetKey, asset.key)
        let plan = AIUpdateSelectionPlan(selection: [.init(key: asset.key, displayName: record.displayName)], assets: inventory.assets, results: [:])
        XCTAssertTrue(plan.hasSelection)
        XCTAssertEqual(plan.unsupported.count, 1)
    }

    func testSupportingCLIsUseExactPackagesAndDoNotUpdateUnrelatedInstallations() throws {
        for (id, package) in [("opencli", "@jackwener/opencli"), ("lark-cli", "@larksuite/cli"), ("botmux", "botmux"), ("agentbuddy", "agentbuddy")] {
            let definition = try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == id })
            let route = CLIUpdateRoute(definition: definition, executableURL: URL(fileURLWithPath: "/fixture/lib/node_modules/\(package)/bin/index.js"))
            XCTAssertEqual(route.capability?.packageIdentifier, package)
            XCTAssertEqual(route.execution?.manager, .npm)
            XCTAssertNil(CLIUpdateRoute(definition: definition, executableURL: URL(fileURLWithPath: "/fixture/bin/\(id)")).execution)
        }
    }

    func testOtherMCPRoleRetainsRealCLIUpdateIdentity() throws {
        let record = cli("botmux", path: "/fixture/lib/node_modules/botmux/bin/index.js")
        let server = MCPServerRecord(name: "botmux", ownerDefinitionID: "codex", sourceURL: URL(fileURLWithPath: "/fixture/config.toml"), transport: .stdio, command: nil, isEnabled: true)
        let tools = OtherAIToolProjection.tools(hooks: [], mcpServers: [server], reclassifiedCLIs: [record])
        XCTAssertEqual(tools.count, 1)
        let inventory = AIUpdateAssetBuilder.inventory(snapshot: nil, managementProjection: .init(records: [record]), projectSkills: [], projectPlugins: [], otherTools: tools)
        let key = AIUpdateIdentity.other(try XCTUnwrap(tools.first), assets: inventory.assets)
        XCTAssertEqual(key, AIUpdateIdentity.cli(record))
        XCTAssertNotEqual(key.canonicalLocation, server.sourceURL.path)
        XCTAssertEqual(inventory.assets.count, 1)
        XCTAssertNotNil(inventory.executionCapabilities[key])
    }

    func testConfigDirectoryNeverBecomesAnExecutableUpdate() throws {
        let tool = OtherAIToolRecord(name: "botmux", kind: .mcpServer, installMethod: .mcpRegistration, affectedAgentIDs: [], url: URL(fileURLWithPath: "/fixture/config.toml"), allocatedSize: 0)
        let inventory = AIUpdateAssetBuilder.inventory(snapshot: nil, managementProjection: .empty, projectSkills: [], projectPlugins: [], otherTools: [tool])
        XCTAssertEqual(inventory.unsupportedResults.count, 1)
        XCTAssertTrue(inventory.executionCapabilities.isEmpty)
        XCTAssertNil(try XCTUnwrap(inventory.assets.first).capability)
    }

    func testCaskMetadataUsesReadOnlyFixedHostAndMarketingVersion() throws {
        let request = UpdateMetadataRequest.homebrewCask(token: "visual-studio-code")
        XCTAssertTrue(UpdateRequestValidator.validate(try XCTUnwrap(request.url), for: request))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "https://evil.example/api/cask/visual-studio-code.json")!, for: request))
        let response = try LocalUpdateMetadataFetcher.parse(Data(#"{"version":"1.105.0,build123"}"#.utf8), request: request)
        XCTAssertEqual(response.latestVersion, "1.105.0")
        XCTAssertNil(ApplicationUpdateRoute.capability(bundleIdentifier: "com.openai.codex"))
        XCTAssertNil(ApplicationUpdateRoute.capability(bundleIdentifier: "com.anthropic.claudefordesktop"))
        XCTAssertNil(ApplicationUpdateRoute.capability(bundleIdentifier: "unknown"))
        let record = AIToolRecord(id: "vscode-app", kind: .application, displayName: "Code", owner: .tool(definitionID: "vscode"), evidence: .init(bundleIdentifier: "com.microsoft.VSCode", applicationURL: URL(fileURLWithPath: "/fixture/Code.app"), detectedVersion: "1.0.0"))
        let inventory = AIUpdateAssetBuilder.inventory(snapshot: nil, managementProjection: .init(records: [record]), projectSkills: [], projectPlugins: [])
        XCTAssertEqual(inventory.assets.first?.capability?.providerKind, .homebrewCask)
        XCTAssertTrue(inventory.executionCapabilities.isEmpty)
    }
}
