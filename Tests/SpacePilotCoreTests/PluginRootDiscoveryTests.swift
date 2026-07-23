import Foundation
import XCTest
@testable import SpacePilotCore

final class PluginRootDiscoveryTests: XCTestCase {
    func testAbsentCacheIsANormalEmptyInstallation() throws {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let access = PluginDiscoveryFixtureAccess(missing: [home.appending(path: ".codex/plugins/cache")])

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testExistingEmptyCacheIsAValidEmptyInstallation() throws {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(directories: [cache: []])

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertTrue(result.diagnostics.isEmpty)
    }

    func testInaccessibleCacheProducesSanitizedDiagnostic() throws {
        let home = URL(fileURLWithPath: "/fixture/private-user", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(unreadableListings: [cache])

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertEqual(result.diagnostics, [.cacheInaccessible])
        XCTAssertFalse(result.diagnostics[0].message.contains(home.path))
    }

    func testInaccessibleSourceAndPluginDirectoriesProduceDiagnostics() throws {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let inaccessibleSource = cache.appending(path: "private-source", directoryHint: .isDirectory)
        let source = cache.appending(path: "curated", directoryHint: .isDirectory)
        let inaccessiblePlugin = source.appending(path: "private-plugin", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(
            directories: [cache: [inaccessibleSource, source], source: [inaccessiblePlugin]],
            unreadableListings: [inaccessibleSource, inaccessiblePlugin]
        )

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertEqual(Set(result.diagnostics), [.sourceInaccessible, .pluginDirectoryInaccessible])
    }

    func testVersionDirectoryIsReturnedEvenWhenItsManifestIsMissing() async throws {
        let tree = try TemporaryTree(files: [:])
        let home = tree.url
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let source = cache.appending(path: "curated", directoryHint: .isDirectory)
        let plugin = source.appending(path: "product-design", directoryHint: .isDirectory)
        let version = plugin.appending(path: "1.0.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: version, withIntermediateDirectories: true)

        let discovery = PluginRootDiscovery(access: LocalFileSystemAccess()).discover(homeDirectory: home)
        let scan = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: discovery.roots)

        XCTAssertEqual(discovery.roots, [version.standardizedFileURL])
        XCTAssertTrue(discovery.diagnostics.isEmpty)
        XCTAssertTrue(scan.diagnostics.contains { $0.hasPrefix("Missing Plugin manifest") })
    }

    func testSymlinkCacheEscapeIsRejected() {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(
            directories: [cache: []],
            symbolicLinks: [cache]
        )

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.diagnostics, [.cacheInaccessible])
    }

    func testSymlinkSourceEscapeIsRejected() {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let source = cache.appending(path: "curated", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(
            directories: [cache: [source], source: []],
            symbolicLinks: [source]
        )

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.diagnostics, [.sourceInaccessible])
    }

    func testSymlinkPluginDirectoryEscapeIsRejected() {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let source = cache.appending(path: "curated", directoryHint: .isDirectory)
        let plugin = source.appending(path: "product-design", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(
            directories: [cache: [source], source: [plugin], plugin: []],
            symbolicLinks: [plugin]
        )

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.diagnostics, [.pluginDirectoryInaccessible])
    }

    func testSymlinkVersionEscapeIsRejected() {
        let home = URL(fileURLWithPath: "/fixture/home", isDirectory: true)
        let cache = home.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        let source = cache.appending(path: "curated", directoryHint: .isDirectory)
        let plugin = source.appending(path: "product-design", directoryHint: .isDirectory)
        let version = plugin.appending(path: "1.0.0", directoryHint: .isDirectory)
        let access = PluginDiscoveryFixtureAccess(
            directories: [
                cache: [source],
                source: [plugin],
                plugin: [version],
                version: []
            ],
            symbolicLinks: [version]
        )

        let result = PluginRootDiscovery(access: access).discover(homeDirectory: home)

        XCTAssertTrue(result.roots.isEmpty)
        XCTAssertEqual(result.diagnostics, [.installationInaccessible])
    }
}

private struct PluginDiscoveryFixtureAccess: FileSystemAccess {
    let directories: [URL: [URL]]
    let missing: Set<URL>
    let unreadableMetadata: Set<URL>
    let unreadableListings: Set<URL>
    let symbolicLinks: Set<URL>

    init(
        directories: [URL: [URL]] = [:],
        missing: Set<URL> = [],
        unreadableMetadata: Set<URL> = [],
        unreadableListings: Set<URL> = [],
        symbolicLinks: Set<URL> = []
    ) {
        self.directories = Dictionary(uniqueKeysWithValues: directories.map {
            ($0.key.standardizedFileURL, $0.value)
        })
        self.missing = Set(missing.map(\.standardizedFileURL))
        self.unreadableMetadata = Set(unreadableMetadata.map(\.standardizedFileURL))
        self.unreadableListings = Set(unreadableListings.map(\.standardizedFileURL))
        self.symbolicLinks = Set(symbolicLinks.map(\.standardizedFileURL))
    }

    func metadata(at url: URL) throws -> FileMetadata {
        let url = url.standardizedFileURL
        if missing.contains(url) { throw CocoaError(.fileNoSuchFile) }
        if unreadableMetadata.contains(url) { throw CocoaError(.fileReadNoPermission) }
        return FileMetadata(
            isDirectory: true,
            isRegularFile: false,
            isSymbolicLink: symbolicLinks.contains(url),
            isPackage: false,
            logicalSize: 0,
            allocatedSize: 0,
            creationDate: nil,
            modificationDate: nil,
            resourceIdentifier: nil
        )
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        let url = url.standardizedFileURL
        if unreadableListings.contains(url) { throw CocoaError(.fileReadNoPermission) }
        return directories[url] ?? []
    }
}
