import XCTest
@testable import SpacePilotCore

final class ApplicationScannerTests: XCTestCase {
    func testReadsBundleIdentifierVersionAndExecutableSize() async throws {
        let fixture = try TestAppBuilder.make(
            name: "Example",
            bundleID: "com.example.Example",
            version: "2.1",
            executableBytes: 512
        )

        let records = try await ApplicationScanner().scan(
            locations: [fixture.appURL.deletingLastPathComponent()]
        )

        XCTAssertEqual(records.first?.bundleIdentifier, "com.example.Example")
        XCTAssertEqual(records.first?.version, "2.1")
        XCTAssertGreaterThanOrEqual(records.first?.allocatedSize ?? 0, 512)
    }

    func testFallsBackToBundleFilenameWhenDeclaredNameIsEmpty() async throws {
        let fixture = try TestAppBuilder.make(
            name: "hintview",
            bundleID: "org.example.hintview",
            version: "1.0",
            executableBytes: 16
        )
        let infoURL = fixture.appURL.appending(path: "Contents/Info.plist")
        let data = try Data(contentsOf: infoURL)
        var info = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
        info["CFBundleName"] = ""
        let updated = try PropertyListSerialization.data(
            fromPropertyList: info,
            format: .xml,
            options: 0
        )
        try updated.write(to: infoURL)

        let records = try await ApplicationScanner().scan(
            locations: [fixture.appURL.deletingLastPathComponent()]
        )

        XCTAssertEqual(records.first?.name, "hintview")
    }

    func testDeduplicatesSameApplicationLocation() async throws {
        let fixture = try TestAppBuilder.make(
            name: "Example",
            bundleID: "com.example.Example",
            version: "1.0",
            executableBytes: 16
        )

        let records = try await ApplicationScanner().scan(locations: [
            fixture.appURL.deletingLastPathComponent(),
            fixture.appURL.deletingLastPathComponent()
        ])

        XCTAssertEqual(records.count, 1)
    }

    func testFindsApplicationsInsideSuiteFoldersWithoutEnteringAppBundles() async throws {
        let tree = try TemporaryTree(files: [:])
        let suite = tree.url.appending(path: "Developer Tools", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
        _ = try TestAppBuilder.make(
            in: suite,
            name: "Suite App",
            bundleID: "com.example.suite-app",
            version: "1.0",
            executableBytes: 16
        )
        let host = try TestAppBuilder.make(
            in: tree.url,
            name: "Host",
            bundleID: "com.example.host",
            version: "1.0",
            executableBytes: 16
        )
        _ = try TestAppBuilder.make(
            in: host.appURL.appending(path: "Contents/Helpers", directoryHint: .isDirectory),
            name: "Host Helper",
            bundleID: "com.example.host.helper",
            version: "1.0",
            executableBytes: 16
        )

        let records = try await ApplicationScanner().scan(locations: [tree.url])

        XCTAssertEqual(Set(records.map(\.name)), ["Host", "Suite App"])
    }

    func testAddsSupplementaryRegisteredApplicationsAndPrefersPrimaryInstall() async throws {
        let tree = try TemporaryTree(files: [:])
        let primary = try TestAppBuilder.make(
            in: tree.url,
            name: "Primary",
            bundleID: "com.example.shared",
            version: "2.0",
            executableBytes: 16
        )
        let duplicate = try TestAppBuilder.make(
            name: "Old Copy",
            bundleID: "com.example.shared",
            version: "1.0",
            executableBytes: 16
        )
        let updater = try TestAppBuilder.make(
            name: "Updater",
            bundleID: "com.example.updater",
            version: "1.0",
            executableBytes: 16
        )
        let scanner = ApplicationScanner(
            supplementaryApplicationURLs: { [duplicate.appURL, updater.appURL] }
        )

        let records = try await scanner.scan(locations: [tree.url])

        XCTAssertEqual(Set(records.map(\.name)), ["Primary", "Updater"])
        XCTAssertEqual(
            records.first(where: { $0.bundleIdentifier == "com.example.shared" })?.url,
            primary.appURL
        )
    }

    func testCachedInventoryDetectsAnApplicationAddedToTheLocation() async throws {
        let fixture = try TestAppBuilder.make(
            name: "First",
            bundleID: "com.example.first",
            version: "1.0",
            executableBytes: 16
        )
        let location = fixture.appURL.deletingLastPathComponent()
        let store = try SQLiteIndexStore(
            url: location.appending(path: "index.sqlite")
        )
        let scanner = ApplicationScanner(cache: store)
        let first = try await scanner.scan(locations: [location])
        let secondFixture = try TestAppBuilder.make(
            in: location,
            name: "Second",
            bundleID: "com.example.second",
            version: "1.0",
            executableBytes: 16
        )
        _ = secondFixture

        let refreshed = try await scanner.scan(locations: [location])

        XCTAssertEqual(first.map(\.name), ["First"])
        XCTAssertEqual(Set(refreshed.map(\.name)), ["First", "Second"])
    }

    func testCachedInventoryDetectsAnApplicationAddedInsideExistingSuiteFolder() async throws {
        let tree = try TemporaryTree(files: [:])
        let suite = tree.url.appending(path: "TeX", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: suite, withIntermediateDirectories: true)
        _ = try TestAppBuilder.make(
            in: suite,
            name: "First",
            bundleID: "com.example.first",
            version: "1.0",
            executableBytes: 16
        )
        let store = try SQLiteIndexStore(url: tree.url.appending(path: "index.sqlite"))
        let scanner = ApplicationScanner(cache: store)
        let first = try await scanner.scan(locations: [tree.url])
        _ = try TestAppBuilder.make(
            in: suite,
            name: "Second",
            bundleID: "com.example.second",
            version: "1.0",
            executableBytes: 16
        )

        let refreshed = try await scanner.scan(locations: [tree.url])

        XCTAssertEqual(first.map(\.name), ["First"])
        XCTAssertEqual(Set(refreshed.map(\.name)), ["First", "Second"])
    }
}
