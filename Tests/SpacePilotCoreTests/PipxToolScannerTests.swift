import XCTest
@testable import SpacePilotCore

final class PipxToolScannerTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotPipx-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeVenv(_ home: URL, root: String, name: String) throws {
        let dir = home.appending(path: "\(root)/\(name)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func testKeepsManagedToolsAndSkipsDenyListedDevTools() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVenv(home, root: "Library/Application Support/pipx/venvs", name: "openviking")
        try makeVenv(home, root: "Library/Application Support/pipx/venvs", name: "black")   // formatter, deny-listed
        try makeVenv(home, root: ".local/share/uv/tools", name: "togo-cli")                 // AI tool, keep
        try makeVenv(home, root: ".local/share/uv/tools", name: "recall-memory")            // AI, keep

        let tools = PipxToolScanner().scan(homeDirectory: home)
        XCTAssertEqual(tools.map(\.name), ["openviking", "recall-memory", "togo-cli"])
    }

    func testDeduplicatesToolInstalledUnderTwoManagers() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVenv(home, root: "Library/Application Support/pipx/venvs", name: "openviking")
        try makeVenv(home, root: ".local/pipx/venvs", name: "openviking")

        let tools = PipxToolScanner().scan(homeDirectory: home)
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?.name, "openviking")
    }

    func testMissingRootsYieldNoTools() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertTrue(PipxToolScanner().scan(homeDirectory: home).isEmpty)
    }

    func testPipxToolsFoldIntoOtherAIToolProjection() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeVenv(home, root: "Library/Application Support/pipx/venvs", name: "openviking")
        let pipx = PipxToolScanner().scan(homeDirectory: home)

        let tools = OtherAIToolProjection.tools(hooks: [], mcpServers: [], pipxTools: pipx)
        let openviking = try XCTUnwrap(tools.first { $0.name == "openviking" })
        XCTAssertEqual(openviking.kind, .packageInstalled)
        XCTAssertEqual(openviking.installMethod, .pipx)
    }
}
