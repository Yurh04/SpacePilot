import XCTest
@testable import SpacePilotCore

final class ApplicationScannerTests: XCTestCase {
    func testReadsBundleIdentifierVersionAndExecutableSize() async throws {
        let fixture = try TestAppBuilder.make(
            name: "Example",
            bundleID: "com.example.Example",
            version: "2.1",
            executableBytes: 512
        )

        let records = try await ApplicationScanner().scan(
            locations: [fixture.appURL.deletingLastPathComponent()]
        )

        XCTAssertEqual(records.first?.bundleIdentifier, "com.example.Example")
        XCTAssertEqual(records.first?.version, "2.1")
        XCTAssertGreaterThanOrEqual(records.first?.allocatedSize ?? 0, 512)
    }

    func testDeduplicatesSameApplicationLocation() async throws {
        let fixture = try TestAppBuilder.make(
            name: "Example",
            bundleID: "com.example.Example",
            version: "1.0",
            executableBytes: 16
        )

        let records = try await ApplicationScanner().scan(locations: [
            fixture.appURL.deletingLastPathComponent(),
            fixture.appURL.deletingLastPathComponent()
        ])

        XCTAssertEqual(records.count, 1)
    }
}
