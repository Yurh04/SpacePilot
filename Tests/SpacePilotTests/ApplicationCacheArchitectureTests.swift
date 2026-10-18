import Foundation
import XCTest

final class ApplicationCacheArchitectureTests: XCTestCase {
    func testCachePageUsesNativeListFiltersAndExistingCleanupReview() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/Views/Cleanup/ApplicationCacheView.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains(".listStyle(.inset)"))
        XCTAssertTrue(source.contains("CacheSafetyFilter"))
        XCTAssertTrue(source.contains("selectedItemIDs"))
        XCTAssertTrue(source.contains("reviewCleanup(selected)"))
        XCTAssertTrue(source.contains("FileSystemItemIcon("))
        XCTAssertTrue(source.contains("ViewThatFits(in: .horizontal)"))
        XCTAssertFalse(source.contains(".listStyle(.sidebar)"))
    }

    func testCachePageIsConnectedToTheRootAndFocusedRefreshScope() throws {
        let root = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/Views/AppRootView.swift"
            ),
            encoding: .utf8
        )
        let model = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/App/AppModel.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(root.contains("case .applicationCaches:"))
        XCTAssertTrue(root.contains("ApplicationCacheView("))
        XCTAssertTrue(root.contains("scan: { model.startScan(scope: .applicationCaches) }"))
        XCTAssertTrue(model.contains("case .applicationCaches:"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
