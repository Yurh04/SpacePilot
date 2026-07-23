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

    func testDiscoversOnlySupportedBundlesInBoundedDirectories() throws {
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
            bundleIdentifier: "com.example.unrelated"
        )
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Nested/Deep.appex",
            bundleIdentifier: "com.example.browser.deep"
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
                "com.example.browser.helper"
            ]
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
