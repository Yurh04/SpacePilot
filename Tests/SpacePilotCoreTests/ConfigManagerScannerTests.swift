import XCTest
@testable import SpacePilotCore

final class ConfigManagerScannerTests: XCTestCase {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotConfigMgr-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func makeDir(_ home: URL, _ relative: String) throws {
        let dir = home.appending(path: relative, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func testReportsKnownManagerWhenConfigDirExists() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir(home, ".cc-switch")

        let tools = ConfigManagerScanner().scan(homeDirectory: home)
        XCTAssertEqual(tools.map(\.name), ["CC Switch"])
        XCTAssertEqual(tools.first?.url.lastPathComponent, ".cc-switch")
    }

    func testMissingConfigDirYieldsNoTools() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        XCTAssertTrue(ConfigManagerScanner().scan(homeDirectory: home).isEmpty)
    }

    func testConfigManagersFoldIntoOtherAIToolProjection() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try makeDir(home, ".cc-switch")
        let managers = ConfigManagerScanner().scan(homeDirectory: home)

        let tools = OtherAIToolProjection.tools(hooks: [], mcpServers: [], configManagers: managers)
        let ccSwitch = try XCTUnwrap(tools.first { $0.name == "CC Switch" })
        XCTAssertEqual(ccSwitch.kind, .configurationManager)
        XCTAssertEqual(ccSwitch.installMethod, .applicationBundle)
    }
}
