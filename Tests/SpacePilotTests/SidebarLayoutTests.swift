import Foundation
import XCTest

final class SidebarLayoutTests: XCTestCase {
    func testPrimarySidebarUsesOneStableWidthAcrossDetailDestinations() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/SpacePilot/Views/SidebarView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("private static let stableWidth: CGFloat = 220"))
        XCTAssertTrue(source.contains("min: Self.stableWidth"))
        XCTAssertTrue(source.contains("ideal: Self.stableWidth"))
        XCTAssertTrue(source.contains("max: Self.stableWidth"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
