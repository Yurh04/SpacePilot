import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationIdentityReaderTests: XCTestCase {
    func testProvidesSecurityBackedDefaultReader() {
        _ = SecurityApplicationSigningMetadataReader()
        _ = ApplicationIdentityReader()
    }

    func testReadsMainEmbeddedAndApplicationGroupIdentifiers() throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .build()
        let signing = StubSigningMetadata(
            teamIdentifier: "TEAM123",
            applicationGroups: ["TEAM123.com.example.shared"]
        )

        let identity = try ApplicationIdentityReader(signingReader: signing)
            .read(application: app.record)

        XCTAssertEqual(identity.applicationID, app.record.id)
        XCTAssertEqual(identity.mainBundleIdentifier, "com.example.browser")
        XCTAssertTrue(
            identity.componentBundleIdentifiers.contains("com.example.browser.widget")
        )
        XCTAssertEqual(identity.teamIdentifier, "TEAM123")
        XCTAssertEqual(identity.applicationGroups, ["TEAM123.com.example.shared"])
        XCTAssertEqual(
            identity.allBundleIdentifiers,
            ["com.example.browser", "com.example.browser.widget"]
        )
    }

    func testDiscoversSupportedBundlesRecursivelyInBoundedDirectories() throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/XPCServices/Service.xpc",
            bundleIdentifier: "com.example.browser.service"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Library/LoginItems/Launcher.app",
            bundleIdentifier: "com.example.browser.launcher"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Helpers/Helper.app",
            bundleIdentifier: "com.example.browser.helper"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/Unrelated.app",
            bundleIdentifier: "com.example.browser.resource"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Nested/Deep.appex",
            bundleIdentifier: "com.example.browser.deep"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Frameworks/Product.framework/Versions/A/Helpers/Renderer.app",
            bundleIdentifier: "com.example.browser.renderer"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/SharedSupport/Components/Import.bundle",
            bundleIdentifier: "com.example.browser.import"
        )
        .build()

        let identity = try ApplicationIdentityReader(
            signingReader: StubSigningMetadata(
                teamIdentifier: nil,
                applicationGroups: []
            )
        )
        .read(application: app.record)

        XCTAssertEqual(
            identity.componentBundleIdentifiers,
            [
                "com.example.browser.widget",
                "com.example.browser.service",
                "com.example.browser.launcher",
                "com.example.browser.helper",
                "com.example.browser.resource",
                "com.example.browser.deep",
                "com.example.browser.renderer",
                "com.example.browser.import"
            ]
        )
    }

    func testHonorsDepthLimit() throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/One/Allowed.app",
            bundleIdentifier: "com.example.allowed"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/One/Two/TooDeep.app",
            bundleIdentifier: "com.example.too-deep"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/SharedSupport/Later.app",
            bundleIdentifier: "com.example.later"
        )
        .build()
        let reader = ApplicationIdentityReader(
            signingReader: StubSigningMetadata(
                teamIdentifier: nil,
                applicationGroups: []
            ),
            discoveryLimits: ApplicationIdentityDiscoveryLimits(
                maximumDepth: 2,
                maximumScannedEntries: 100
            )
        )

        let identity = try reader.read(application: app.record)

        XCTAssertTrue(
            identity.componentBundleIdentifiers.contains("com.example.allowed")
        )
        XCTAssertFalse(
            identity.componentBundleIdentifiers.contains("com.example.too-deep")
        )
    }

    func testReadsFlatBundleInfoPlist() throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/Import.bundle",
            bundleIdentifier: "com.example.import"
        )
        .build()
        let bundle = app.record.url.appending(
            path: "Contents/Resources/Import.bundle"
        )
        try FileManager.default.moveItem(
            at: bundle.appending(path: "Contents/Info.plist"),
            to: bundle.appending(path: "Info.plist")
        )

        let identity = try makeReader().read(application: app.record)

        XCTAssertTrue(
            identity.componentBundleIdentifiers.contains("com.example.import")
        )
    }

    func testHonorsGlobalEntryLimitAcrossDiscoveryRoots() throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/SharedSupport/First.app",
            bundleIdentifier: "com.example.first"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/Second.app",
            bundleIdentifier: "com.example.second"
        )
        .build()
        let reader = ApplicationIdentityReader(
            signingReader: StubSigningMetadata(
                teamIdentifier: nil,
                applicationGroups: []
            ),
            discoveryLimits: ApplicationIdentityDiscoveryLimits(
                maximumDepth: 6,
                maximumScannedEntries: 1
            )
        )

        let identity = try reader.read(application: app.record)

        XCTAssertEqual(
            identity.componentBundleIdentifiers,
            ["com.example.first"]
        )
    }

    func testStopsImmediatelyWhenTaskIsCancelled() async throws {
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/Resources/Component.app",
            bundleIdentifier: "com.example.component"
        )
        .build()
        let reader = makeReader()
        let task = Task {
            return try reader.read(application: app.record)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
    }

    func testRejectsAllowedDirectorySymlinkEscapingApplicationBundle() throws {
        let outside = try TestAppBuilder(
            name: "Outside",
            bundleIdentifier: "com.example.outside"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/External.appex",
            bundleIdentifier: "com.example.external"
        )
        .build()
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .build()
        try FileManager.default.createSymbolicLink(
            at: app.record.url.appending(path: "Contents/PlugIns"),
            withDestinationURL: outside.record.url.appending(path: "Contents/PlugIns")
        )

        let identity = try makeReader().read(application: app.record)

        XCTAssertEqual(identity.componentBundleIdentifiers, [])
    }

    func testRejectsEmbeddedBundleSymlinkEscapingApplicationBundle() throws {
        let outside = try TestAppBuilder(
            name: "Outside",
            bundleIdentifier: "com.example.outside"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/External.appex",
            bundleIdentifier: "com.example.external"
        )
        .build()
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .build()
        try FileManager.default.createSymbolicLink(
            at: app.record.url.appending(path: "Contents/PlugIns/Escaped.appex"),
            withDestinationURL: outside.record.url.appending(
                path: "Contents/PlugIns/External.appex"
            )
        )

        let identity = try makeReader().read(application: app.record)

        XCTAssertEqual(
            identity.componentBundleIdentifiers,
            ["com.example.browser.widget"]
        )
    }

    func testRejectsInternalBundleSymlinksEscapingApplicationBundle() throws {
        let outside = try TestAppBuilder(
            name: "Outside",
            bundleIdentifier: "com.example.external"
        )
        .build()
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/EscapedInfo.appex",
            bundleIdentifier: "com.example.browser.escaped-info"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/EscapedContents.appex",
            bundleIdentifier: "com.example.browser.escaped-contents"
        )
        .build()
        try replaceWithSymbolicLink(
            app.record.url.appending(
                path: "Contents/PlugIns/EscapedInfo.appex/Contents/Info.plist"
            ),
            destination: outside.record.url.appending(path: "Contents/Info.plist")
        )
        try replaceWithSymbolicLink(
            app.record.url.appending(
                path: "Contents/PlugIns/EscapedContents.appex/Contents"
            ),
            destination: outside.record.url.appending(path: "Contents")
        )

        let identity = try makeReader().read(application: app.record)

        XCTAssertEqual(
            identity.componentBundleIdentifiers,
            ["com.example.browser.widget"]
        )
    }

    func testRejectsMainBundleInfoSymlinkEscapingApplicationBundle() throws {
        let outside = try TestAppBuilder(
            name: "Outside",
            bundleIdentifier: "com.example.external"
        )
        .build()
        let app = try TestAppBuilder(
            name: "Browser",
            bundleIdentifier: "com.example.browser"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .build()
        try replaceWithSymbolicLink(
            app.record.url.appending(path: "Contents/Info.plist"),
            destination: outside.record.url.appending(path: "Contents/Info.plist")
        )

        let identity = try makeReader().read(application: app.record)

        XCTAssertNil(identity.mainBundleIdentifier)
        XCTAssertEqual(
            identity.componentBundleIdentifiers,
            ["com.example.browser.widget"]
        )
    }

    private func makeReader() -> ApplicationIdentityReader {
        ApplicationIdentityReader(
            signingReader: StubSigningMetadata(
                teamIdentifier: nil,
                applicationGroups: []
            )
        )
    }

    private func replaceWithSymbolicLink(
        _ url: URL,
        destination: URL
    ) throws {
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(
            at: url,
            withDestinationURL: destination
        )
    }
}

private struct StubSigningMetadata: ApplicationSigningMetadataReading {
    let result: ApplicationSigningMetadata

    init(teamIdentifier: String?, applicationGroups: Set<String>) {
        result = ApplicationSigningMetadata(
            teamIdentifier: teamIdentifier,
            applicationGroups: applicationGroups
        )
    }

    func metadata(at applicationURL: URL) throws -> ApplicationSigningMetadata {
        result
    }
}
