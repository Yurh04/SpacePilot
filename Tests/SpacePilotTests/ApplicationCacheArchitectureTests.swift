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
        XCTAssertTrue(root.contains("CleanupCenterView("))
        XCTAssertTrue(root.contains("scanApplicationCaches:"))
        XCTAssertTrue(root.contains("model.startScan(scope: .applicationCaches)"))
        XCTAssertTrue(model.contains("case .applicationCaches:"))
    }

    func testCleanupCenterOwnsRecommendedApplicationAndDeveloperSections() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilot/Views/Cleanup/CleanupCenterView.swift"
            ),
            encoding: .utf8
        )
        let navigation = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilotCore/Models/NavigationDestination.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("case recommended"))
        XCTAssertTrue(source.contains("case applicationCaches"))
        XCTAssertTrue(source.contains("case developerTools"))
        XCTAssertTrue(source.contains("ApplicationCacheView("))
        XCTAssertTrue(source.contains("DeveloperStorageView("))
        XCTAssertTrue(source.contains("RecommendedCleanupView("))
        XCTAssertFalse(navigation.contains("case developerTools"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
