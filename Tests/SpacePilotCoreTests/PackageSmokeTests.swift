import XCTest
@testable import SpacePilotCore

final class PackageSmokeTests: XCTestCase {
    func testNavigationDestinationsHaveStableTitles() {
        XCTAssertEqual(NavigationDestination.allCases.map(\.title), [
            "Overview",
            "Storage",
            "Applications",
            "Developer & AI",
            "Cleanup History"
        ])
    }
}
