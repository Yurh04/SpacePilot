import Foundation
import XCTest

final class ReleaseWorkflowArchitectureTests: XCTestCase {
    func testReleaseScriptFailsFastWhenOnlyCommandLineToolsAreSelected() throws {
        let source = try source(at: "script/test_release.sh")

        XCTAssertTrue(source.contains("require_full_xcode()"))
        XCTAssertTrue(source.contains("xcode-select -p"))
        XCTAssertTrue(source.contains("/Library/Developer/CommandLineTools"))
        XCTAssertTrue(source.contains("requires full Xcode 16+ with XCTest support"))
        XCTAssertTrue(source.contains("sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"))
        XCTAssertTrue(source.contains("require_full_xcode"))
    }

    func testReadmeDocumentsFullXcodeRequirementBeforeTestsAndReleaseChecks() throws {
        let readme = try source(at: "README.md")

        XCTAssertTrue(readme.contains("完整 Xcode 设为当前开发目录"))
        XCTAssertTrue(readme.contains("no such module 'XCTest'"))
        XCTAssertTrue(readme.contains("xcode-select -p"))
        XCTAssertTrue(readme.contains("sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"))
        XCTAssertTrue(readme.contains("/Library/Developer/CommandLineTools"))
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
