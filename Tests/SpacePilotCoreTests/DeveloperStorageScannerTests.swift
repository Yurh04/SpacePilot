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
        XCTAssertEqual(result.items.first { $0.url.path.contains("_cacache") }?.risk, .rebuildable)
        XCTAssertEqual(result.items.first { $0.url.path.contains("Homebrew") }?.risk, .rebuildable)
        XCTAssertEqual(result.items.first { $0.url.path.contains("pip") }?.risk, .rebuildable)
        XCTAssertTrue(result.items.filter { $0.risk == .rebuildable }.allSatisfy {
            $0.cleanupPolicyScope == .developerStorage
                && $0.cleanupPolicyRelativePath != nil
        })
    }

    func testValidDirectoryStatAvoidsRecursiveRecalculation() async throws {
        let tree = try TemporaryTree(files: [
            ".npm/_cacache/index": 20
        ])
        let root = tree.url.appending(
            path: ".npm/_cacache",
            directoryHint: .isDirectory
        )
        let scanner = DeveloperStorageScanner(
            directoryStats: FixedDirectoryStatProvider([
                root: (logical: 41_000, allocated: 52_000)
            ])
        )

        let result = try await scanner.scan(homeDirectory: tree.url)
        let item = try XCTUnwrap(result.items.first)

        XCTAssertEqual(item.logicalSize, 41_000)
        XCTAssertEqual(item.allocatedSize, 52_000)
    }

    func testRecognizesExpandedToolCachesButDoesNotOfferArchivesOrSimulatorDataForCleanup() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Developer/Xcode/iOS DeviceSupport/17/symbols": 31,
            ".m2/repository/org/example.jar": 32,
            "Library/Caches/ms-playwright/chromium/browser": 33,
            "Library/Developer/Xcode/Archives/App.xcarchive/app": 34,
            "Library/Developer/CoreSimulator/Devices/device/data.db": 35
        ])

        let result = try await DeveloperStorageScanner().scan(homeDirectory: tree.url)
        let cleanupItems = result.items.filter {
            $0.cleanupPolicyScope == .developerStorage
        }

        XCTAssertEqual(cleanupItems.count, 3)
        XCTAssertTrue(cleanupItems.allSatisfy { $0.risk == .rebuildable })
        XCTAssertFalse(cleanupItems.contains { $0.url.path.contains("Archives") })
        XCTAssertFalse(cleanupItems.contains { $0.url.path.contains("CoreSimulator") })
    }
}
