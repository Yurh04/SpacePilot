import Foundation
import XCTest
@testable import SpacePilotCore

final class DirectoryScannerTests: XCTestCase {
    func testScannerRecordsUnreadablePathsAndContinues() async throws {
        let fixture = try TemporaryTree(files: ["a.bin": 100, "nested/b.bin": 200])
        let nested = fixture.url.appending(path: "nested", directoryHint: .isDirectory)
        let access = FixtureFileSystemAccess(unreadable: [nested])

        let result = try await DirectoryScanner(access: access).scan(
            root: fixture.url,
            options: .init(category: .personal, risk: .sensitive)
        )

        XCTAssertEqual(result.items.map(\.logicalSize).reduce(0, +), 100)
        XCTAssertEqual(result.coverage.deniedPaths.map(\.standardizedFileURL), [nested.standardizedFileURL])
    }

    func testScannerDoesNotFollowSymbolicLinks() async throws {
        let fixture = try TemporaryTree(files: ["actual/file.bin": 64])
        let link = fixture.url.appending(path: "linked")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.url.appending(path: "actual")
        )

        let result = try await DirectoryScanner(access: LocalFileSystemAccess()).scan(
            root: fixture.url,
            options: .init(category: .personal, risk: .sensitive)
        )

        XCTAssertEqual(result.items.filter { $0.url.lastPathComponent == "file.bin" }.count, 1)
    }

    func testBoundedScanRetainsOnlyLargestItemsButCountsEveryFile() async throws {
        let fixture = try TemporaryTree(files: [
            "small.bin": 10,
            "medium.bin": 20,
            "large.bin": 30,
            "nested/largest.bin": 40
        ])

        let result = try await DirectoryScanner(access: LocalFileSystemAccess()).scan(
            root: fixture.url,
            options: .init(
                category: .personal,
                risk: .sensitive,
                retainedItemLimit: 2
            )
        )

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), [
            "largest.bin", "large.bin"
        ])
        XCTAssertEqual(result.fileCount, 4)
        XCTAssertEqual(result.totalLogicalSize, 100)
        XCTAssertGreaterThanOrEqual(
            result.totalAllocatedSize,
            result.items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        )
    }
}
