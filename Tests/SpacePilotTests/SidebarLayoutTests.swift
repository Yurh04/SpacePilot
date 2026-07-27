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
        XCTAssertTrue(source.contains(".frame(width: Self.stableWidth)"))
        XCTAssertTrue(source.contains("min: Self.stableWidth"))
        XCTAssertTrue(source.contains("ideal: Self.stableWidth"))
        XCTAssertTrue(source.contains("max: Self.stableWidth"))
    }

    func testStorageCategoryBrowserDoesNotDeclareAnotherSidebar() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appending(path: "Sources/SpacePilot/Views/Storage/StorageView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".listStyle(.inset)"))
        XCTAssertFalse(source.contains(".listStyle(.sidebar)"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
