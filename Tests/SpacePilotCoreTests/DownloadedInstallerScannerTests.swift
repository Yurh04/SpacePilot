import Foundation
import XCTest
@testable import SpacePilotCore

final class DownloadedInstallerScannerTests: XCTestCase {
    func testFindsOnlySupportedInstallerForUniquelyMatchedInstalledApplication() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/GoogleChrome-152.0.7977.83-arm64.dmg": 128,
            "Downloads/GoogleChrome-backup.dmg": 64,
            "Downloads/GoogleChrome.zip": 32,
            "Downloads/Nested/GoogleChrome.pkg": 16,
            "Applications/Google Chrome.app/Contents/MacOS/Google Chrome": 8
        ])
        let application = ApplicationRecord(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            version: "152.0.7977.83",
            url: fixture.url.appending(path: "Applications/Google Chrome.app"),
            executableURL: nil,
            allocatedSize: 8
        )

        let result = try await DownloadedInstallerScanner(
            access: LocalFileSystemAccess()
        ).scan(
            downloadsDirectory: fixture.url.appending(path: "Downloads"),
            applications: [application]
        )

        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(item.url.lastPathComponent, "GoogleChrome-152.0.7977.83-arm64.dmg")
        XCTAssertEqual(item.category, .installer)
        XCTAssertEqual(item.risk, .safe)
        XCTAssertEqual(item.ownerID, application.id)
        XCTAssertEqual(item.explanation, "Installer for installed application: Google Chrome")
    }

    func testBundleIdentifierLeafCanMatchInstallerName() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/VSCode-darwin-universal.pkg": 128
        ])
        let application = ApplicationRecord(
            name: "Code",
            bundleIdentifier: "com.microsoft.VSCode",
            version: "1.0",
            url: fixture.url.appending(path: "Applications/Visual Studio Code.app"),
            executableURL: nil,
            allocatedSize: 8
        )

        let result = try await DownloadedInstallerScanner(
            access: LocalFileSystemAccess()
        ).scan(
            downloadsDirectory: fixture.url.appending(path: "Downloads"),
            applications: [application]
        )

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), [
            "VSCode-darwin-universal.pkg"
        ])
    }

    func testDoesNotMatchInstallerWhenProductAliasIsAmbiguous() async throws {
        let fixture = try TemporaryTree(files: ["Downloads/Studio.dmg": 128])
        let bundleIdentifiers: [String] = ["com.first.Studio", "com.second.Studio"]
        let applications = bundleIdentifiers.map { bundleID in
            ApplicationRecord(
                name: "Studio",
                bundleIdentifier: bundleID,
                version: "1.0",
                url: fixture.url.appending(path: "Applications/\(bundleID).app"),
                executableURL: nil,
                allocatedSize: 8
            )
        }

        let result = try await DownloadedInstallerScanner(
            access: LocalFileSystemAccess()
        ).scan(
            downloadsDirectory: fixture.url.appending(path: "Downloads"),
            applications: applications
        )

        XCTAssertTrue(result.items.isEmpty)
    }

    func testDoesNotTreatRegisteredHelperOutsideApplicationFoldersAsInstalledProduct() async throws {
        let fixture = try TemporaryTree(files: [
            "Downloads/Updater.dmg": 128,
            "Library/Application Support/Vendor/Updater.app/Contents/MacOS/Updater": 8
        ])
        let helper = ApplicationRecord(
            name: "Updater",
            bundleIdentifier: "com.example.Updater",
            version: "1.0",
            url: fixture.url.appending(
                path: "Library/Application Support/Vendor/Updater.app"
            ),
            executableURL: nil,
            allocatedSize: 8
        )

        let result = try await DownloadedInstallerScanner(
            access: LocalFileSystemAccess()
        ).scan(
            downloadsDirectory: fixture.url.appending(path: "Downloads"),
            applications: [helper]
        )

        XCTAssertTrue(result.items.isEmpty)
    }

    func testReportsUnreadableDownloadsWithoutClaimingCompleteCoverage() async throws {
        let fixture = try TemporaryTree(files: ["Downloads/App.dmg": 128])
        let downloads = fixture.url.appending(path: "Downloads")

        let result = try await DownloadedInstallerScanner(
            access: FixtureFileSystemAccess(unreadable: [downloads])
        ).scan(downloadsDirectory: downloads, applications: [])

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.deniedPaths, [downloads.standardizedFileURL])
        XCTAssertFalse(result.coverage.isComplete)
    }
}
