import Foundation
import XCTest
@testable import SpacePilotCore

final class InstallerPackageScannerTests: XCTestCase {
    func testDiscoversInstallersAndIgnoresUnrelatedFiles() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Foo 1.0.dmg": 1_024,
            "Downloads/Bar.pkg/Payload": 4_096,
            "Downloads/Bar.pkg/Scripts/postinstall": 256,
            "Downloads/Baz.mpkg/Payload": 512,
            "Downloads/notes.txt": 64,
            "Downloads/archive.zip": 128,
            "Downloads/Qux.app/Contents/MacOS/Qux": 512,
            "Downloads/.hidden.dmg": 2_048,
            "Downloads/nested/Deep.dmg": 300,
            "Downloads/a/b/DeepB.dmg": 200,
            "Downloads/a/b/c/DeepC.dmg": 150,
            "Downloads/a/b/c/d/DeepD.dmg": 9_999,
            "Downloads/a/b/c/d/TooDeep.pkg/Payload": 9_999,
            "Desktop/Setup.dmg": 700
        ])

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [
            fixture.url.appending(path: "Downloads"),
            fixture.url.appending(path: "Desktop")
        ])

        let names = Set(result.items.map(\.url.lastPathComponent))
        XCTAssertTrue(names.contains("Foo 1.0.dmg"))
        XCTAssertTrue(names.contains("Bar.pkg"))
        XCTAssertTrue(names.contains("Baz.mpkg"))
        XCTAssertTrue(names.contains("Setup.dmg"))
        XCTAssertTrue(names.contains("Deep.dmg"))
        XCTAssertTrue(names.contains("DeepB.dmg"))
        XCTAssertTrue(names.contains("DeepC.dmg"))
        XCTAssertFalse(names.contains("DeepD.dmg"))
        XCTAssertFalse(names.contains("TooDeep.pkg"))
        XCTAssertFalse(names.contains("notes.txt"))
        XCTAssertFalse(names.contains("archive.zip"))
        XCTAssertFalse(names.contains(".hidden.dmg"))
        // Bundles are not traversed, so their contents never appear as items.
        XCTAssertFalse(names.contains("Qux"))
        XCTAssertFalse(names.contains("Qux.app"))
    }

    func testInstallerItemsAreClassifiedAsSafeInstallers() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Foo.dmg": 100,
            "Downloads/Bar.pkg/Payload": 100
        ])

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [fixture.url.appending(path: "Downloads")])

        XCTAssertEqual(Set(result.items.map(\.category)), [.installer])
        XCTAssertEqual(Set(result.items.map(\.risk)), [.safe])
        XCTAssertTrue(result.items.allSatisfy {
            $0.explanation == InstallerPackageScanner<
                LocalFileSystemAccess
            >.explanation
        })
    }

    func testPackageDirectoriesUseRecursiveSizeAndReportContainedBytes() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Bar.pkg/Payload": 4_096,
            "Downloads/Bar.pkg/Scripts/postinstall": 256
        ])
        let pkgURL = fixture.url.appending(path: "Downloads/Bar.pkg")
        let expectedPayload = try pkgURL
            .appending(path: "Payload")
            .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        let expectedScript = try pkgURL
            .appending(path: "Scripts/postinstall")
            .resourceValues(forKeys: [.totalFileAllocatedSizeKey])
        let expectedAllocated = Int64(
            (expectedPayload.totalFileAllocatedSize ?? 4_096)
                + (expectedScript.totalFileAllocatedSize ?? 256)
        )

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [fixture.url.appending(path: "Downloads")])

        let pkgItem = try XCTUnwrap(result.items.first {
            $0.url.lastPathComponent == "Bar.pkg"
        })
        XCTAssertEqual(pkgItem.logicalSize, 4_352)
        XCTAssertEqual(pkgItem.allocatedSize, expectedAllocated)
        XCTAssertEqual(result.packageContainedLogicalSize, 4_352)
        XCTAssertEqual(result.packageContainedAllocatedSize, expectedAllocated)
        XCTAssertEqual(result.packageContainedFileCount, 2)
    }

    func testMatchesAreCaseInsensitive() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/FOO.DMG": 10,
            "Downloads/Setup.PKG/Payload": 20
        ])

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [fixture.url.appending(path: "Downloads")])

        XCTAssertEqual(
            Set(result.items.map(\.url.lastPathComponent)),
            ["FOO.DMG", "Setup.PKG"]
        )
    }

    func testMissingAndNonDirectoryRootsAreIgnored() async throws {
        let fixture = try TemporaryTree(files: ["Downloads/Foo.dmg": 10])

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [
            fixture.url.appending(path: "Missing"),
            fixture.url.appending(path: "Downloads/Foo.dmg")
        ])

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.coverage.deniedPaths.isEmpty)
    }

    func testUnreadableRootIsRecordedAsCoverageGap() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Foo.dmg": 10,
            "Secret/Bar.dmg": 20
        ])
        let secret = fixture.url.appending(path: "Secret")
        let access = FixtureFileSystemAccess(unreadable: [secret])

        let result = try await InstallerPackageScanner(access: access).scan(roots: [
            fixture.url.appending(path: "Downloads"),
            secret
        ])

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), ["Foo.dmg"])
        XCTAssertEqual(
            result.coverage.deniedPaths.map(\.standardizedFileURL),
            [secret.standardizedFileURL]
        )
    }

    func testRetainedItemLimitKeepsLargestInstallers() async throws {
        var files: [String: Int] = [:]
        for index in 0..<5 {
            files["Downloads/app-\(index).dmg"] = 100 + index * 100
        }
        let fixture = try TemporaryTree(files: files)

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess(),
            retainedItemLimit: 2
        ).scan(roots: [fixture.url.appending(path: "Downloads")])

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), [
            "app-4.dmg", "app-3.dmg"
        ])
    }

    func testSymbolicLinksToInstallersAreNotFollowed() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Real.dmg": 100,
            "Other/LinkTarget.pkg/Payload": 200
        ])
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appending(path: "Downloads/Link.pkg"),
            withDestinationURL: fixture.url.appending(path: "Other/LinkTarget.pkg")
        )

        let result = try await InstallerPackageScanner(
            access: LocalFileSystemAccess()
        ).scan(roots: [fixture.url.appending(path: "Downloads")])

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), ["Real.dmg"])
    }
}
