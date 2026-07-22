import XCTest
@testable import SpacePilotCore

final class DeveloperStorageScannerTests: XCTestCase {
    func testRecognizedDeveloperRootsAreSummarizedWithoutReadingContentBodies() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Developer/Xcode/DerivedData/App/Build/product": 50,
            "Library/Developer/CoreSimulator/Devices/device/data.db": 60,
            ".npm/_cacache/index": 20,
            "Library/Caches/Homebrew/download": 22,
            ".cache/pip/wheel": 24
        ])

        let result = try await DeveloperStorageScanner().scan(homeDirectory: tree.url)

        XCTAssertEqual(result.items.count, 5)
        XCTAssertTrue(result.items.allSatisfy { $0.category == .developer })
        XCTAssertEqual(result.items.first { $0.url.path.contains("DerivedData") }?.risk, .rebuildable)
        XCTAssertEqual(result.items.first { $0.url.path.contains("CoreSimulator") }?.risk, .sensitive)
        XCTAssertEqual(result.items.first { $0.url.path.contains("_cacache") }?.risk, .safe)
        XCTAssertEqual(result.items.first { $0.url.path.contains("Homebrew") }?.risk, .safe)
        XCTAssertEqual(result.items.first { $0.url.path.contains("pip") }?.risk, .safe)
    }
}
