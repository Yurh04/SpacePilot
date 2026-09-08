import Foundation
import XCTest
@testable import SpacePilotCore

final class RegisteredApplicationDiscoveryTests: XCTestCase {
    func testKeepsInstalledSupportAppsAndRejectsBuildArtifactsAndNestedHelpers() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let candidates = [
            "/Applications/TeX/TeXShop.app",
            "/Users/example/Library/Application Support/Google/GoogleUpdater/1/GoogleUpdater.app",
            "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
            "/Users/example/anaconda3/Anaconda-Navigator.app",
            "/Applications/Editor.app/Contents/Frameworks/Editor Helper.app",
            "/Users/example/Library/Developer/Xcode/DerivedData/App/Build/Products/App.app",
            "/Users/example/AI/Project/dist/Project.app",
            "/Library/Application Support/Script Editor/Templates/Droplets/Template.app"
        ].map { URL(fileURLWithPath: $0) }
        let discovery = RegisteredApplicationDiscovery(
            homeDirectory: home,
            query: { candidates }
        )

        let result = discovery.applicationURLs().map(\.path)

        XCTAssertEqual(Set(result), [
            "/Applications/TeX/TeXShop.app",
            "/Users/example/Library/Application Support/Google/GoogleUpdater/1/GoogleUpdater.app",
            "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
            "/Users/example/anaconda3/Anaconda-Navigator.app"
        ])
    }
}
