import XCTest
@testable import SpacePilotCore

final class AIInstallSourceTests: XCTestCase {
    private func classify(_ path: String) -> AIInstallSource {
        AIInstallSource.classify(executableURL: URL(fileURLWithPath: path))
    }

    func testClassifiesKnownLayouts() {
        XCTAssertEqual(classify("/opt/homebrew/bin/lark-cli"), .homebrew)
        XCTAssertEqual(classify("/usr/local/bin/tool"), .homebrew)
        XCTAssertEqual(classify("/Users/x/.local/share/fnm/node-versions/v20/installation/bin/codex"), .npm)
        XCTAssertEqual(classify("/opt/homebrew/lib/node_modules/@dp/one-cli/dist/one.js"), .npm)
        XCTAssertEqual(classify("/Users/x/.local/pipx/venvs/aider/bin/aider"), .pipx)
        XCTAssertEqual(classify("/Users/x/.local/bin/merlin-cli"), .local)
    }

    func testUnknownForEmptyOrUnrecognised() {
        XCTAssertEqual(AIInstallSource.classify(executableURL: nil), .unknown)
        XCTAssertEqual(classify("/some/random/place/tool"), .unknown)
    }

    func testNodeModulesWinsOverHomebrewPrefix() {
        // A node package symlinked under Homebrew's lib should read as npm, not
        // Homebrew, because the more specific manager layout takes precedence.
        XCTAssertEqual(classify("/opt/homebrew/lib/node_modules/x/cli.js"), .npm)
    }

    func testOtherToolInstallMethodMapping() {
        XCTAssertEqual(AIInstallSource.homebrew.otherToolInstallMethod, .homebrew)
        XCTAssertEqual(AIInstallSource.npm.otherToolInstallMethod, .npm)
        XCTAssertEqual(AIInstallSource.pipx.otherToolInstallMethod, .npm)
        XCTAssertEqual(AIInstallSource.local.otherToolInstallMethod, .unknown)
        XCTAssertEqual(AIInstallSource.unknown.otherToolInstallMethod, .unknown)
    }
}
