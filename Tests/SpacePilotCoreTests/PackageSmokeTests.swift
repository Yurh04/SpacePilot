import XCTest
@testable import SpacePilotCore

final class PackageSmokeTests: XCTestCase {
    func testNavigationDestinationsHaveStableRawValues() {
        XCTAssertEqual(NavigationDestination.allCases.map(\.rawValue), [
            "overview",
            "storage",
            "applications",
            "developerAI",
            "history"
        ])
    }

    func testAIApplicationTabsHaveStableRawValues() {
        XCTAssertEqual(AIApplicationTab.allCases.map(\.rawValue), [
            "overview", "dataStorage", "plugins", "skills"
        ])
    }
}
