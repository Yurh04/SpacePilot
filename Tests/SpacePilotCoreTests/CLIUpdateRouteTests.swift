import XCTest
@testable import SpacePilotCore

final class CLIUpdateRouteTests: XCTestCase {
    private func route(_ id: String, _ path: String) throws -> CLIUpdateRoute {
        CLIUpdateRoute(
            definition: try XCTUnwrap(KnownAIToolDefinitions.all.first { $0.id == id }),
            executableURL: URL(fileURLWithPath: path)
        )
    }

    func testNpmAgentRoutesUseFixedPackageAndExactInstallation() throws {
        for (id, package) in [
            ("codex", "@openai/codex"),
            ("relay", "@bytedance-relay/claude-code"),
            ("pi", "@earendil-works/pi-coding-agent")
        ] {
            let path = "/fixture/.local/share/fnm/node-versions/v24/installation/lib/node_modules/\(package)/cli.js"
            let route = try route(id, path)
            XCTAssertEqual(route.capability?.packageIdentifier, package)
            XCTAssertEqual(route.execution?.manager, .npm)
            XCTAssertEqual(route.execution?.installationURL?.path, path)
        }
    }

    func testNativeClaudeAndUvAndBrewDoNotInstallAnNpmCopy() throws {
        XCTAssertEqual(try route("claude", "/fixture/.local/share/claude/versions/2.1.0").execution?.manager, .claudeNative)
        XCTAssertEqual(try route("aime", "/fixture/.local/share/uv/tools/togo-cli/bin/aime").execution?.manager, .uv)
        XCTAssertEqual(try route("aider", "/fixture/.local/pipx/venvs/aider-chat/bin/aider").execution?.manager, .pipx)
        XCTAssertEqual(try route("ollama", "/opt/homebrew/Cellar/ollama/0.1.0/bin/ollama").execution?.manager, .homebrew)
        XCTAssertNil(try route("codex", "/Applications/ChatGPT.app/Contents/Resources/codex").execution)
        XCTAssertNil(try route("codex", "/fixture/unrelated/codex").execution)
    }

    private struct Locator: ExecutableLocating {
        let paths: Set<String>
        func isExecutableFile(at url: URL) -> Bool { paths.contains(url.path) }
        func canonicalExecutable(at url: URL) -> URL { url }
    }

    func testFnmManagerAndEnvironmentStayInInstalledNodeVersion() throws {
        let prefix = "/fixture/.local/share/fnm/node-versions/v24/installation"
        let installed = URL(fileURLWithPath: prefix + "/lib/node_modules/@openai/codex/bin/codex.js")
        let npm = URL(fileURLWithPath: prefix + "/bin/npm")
        let locator = LocalUpdateManagerLocator(
            homeDirectory: URL(fileURLWithPath: "/fixture"),
            locator: Locator(paths: [npm.path, "/opt/homebrew/bin/npm"])
        )
        XCTAssertEqual(locator.locate(.npm, installationURL: installed, packageIdentifier: "@openai/codex"), npm)
        let env = AIUpdateExecutor.environment(
            homeDirectory: URL(fileURLWithPath: "/fixture"), executable: npm,
            manager: .npm, installationURL: installed, package: "@openai/codex"
        )
        XCTAssertEqual(env["NPM_CONFIG_PREFIX"], prefix)
        XCTAssertTrue(env["PATH"]?.hasPrefix(prefix + "/bin:") == true)
        XCTAssertNil(locator.locate(
            .npm, installationURL: URL(fileURLWithPath: "/untrusted/lib/node_modules/@openai/codex/index.js"),
            packageIdentifier: "@openai/codex"
        ))
    }

    func testNoFallbackToDifferentNpmWhenMatchingManagerMissing() {
        let locator = LocalUpdateManagerLocator(
            homeDirectory: URL(fileURLWithPath: "/fixture"),
            locator: Locator(paths: ["/opt/homebrew/bin/npm"])
        )
        XCTAssertNil(locator.locate(
            .npm,
            installationURL: URL(fileURLWithPath: "/fixture/.nvm/versions/node/v24/lib/node_modules/@openai/codex/cli.js"),
            packageIdentifier: "@openai/codex"
        ))
    }

    func testNewUpdateArgumentsAndMetadataStayBounded() throws {
        XCTAssertEqual(AIUpdateExecutor.arguments(manager: .claudeNative, packageIdentifier: "@anthropic-ai/claude-code", targetVersion: "2.1.0"), ["install", "2.1.0"])
        XCTAssertEqual(AIUpdateExecutor.arguments(manager: .uv, packageIdentifier: "togo-cli", targetVersion: "5.25.1"), ["tool", "install", "--upgrade", "togo-cli==5.25.1"])
        let brew = UpdateMetadataRequest.homebrew(formula: "ollama")
        XCTAssertTrue(UpdateRequestValidator.validate(try XCTUnwrap(brew.url), for: brew))
        XCTAssertEqual(
            try LocalUpdateMetadataFetcher.parse(Data(#"{"versions":{"stable":"0.1.0"}}"#.utf8), request: brew).latestVersion,
            "0.1.0"
        )
        let npm = UpdateMetadataRequest.npm(package: "@openai/codex")
        XCTAssertTrue(npm.url?.path.hasSuffix("/latest") == true)
        XCTAssertEqual(try LocalUpdateMetadataFetcher.parse(Data(#"{"version":"1.2.3"}"#.utf8), request: npm).latestVersion, "1.2.3")
    }
}
