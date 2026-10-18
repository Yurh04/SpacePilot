import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationCacheScannerTests: XCTestCase {
    func testFindsOnlyExactInstalledApplicationCacheRoots() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Caches/com.example.Editor/cache.bin": 64,
            "Library/Containers/com.example.Editor/Data/Library/Caches/thumbs.db": 96,
            "Library/Caches/com.example.Unknown/cache.bin": 128,
            "Library/Caches/com.apple.Safari/cache.bin": 256
        ])
        let editor = application(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            root: tree.url
        )
        let safari = application(
            name: "Safari",
            bundleIdentifier: "com.apple.Safari",
            root: tree.url
        )

        let result = try await ApplicationCacheScanner(
            access: LocalFileSystemAccess()
        ).scan(homeDirectory: tree.url, applications: [editor, safari])

        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(Set(result.items.map(\.ownerID)), [editor.id])
        XCTAssertTrue(result.items.allSatisfy { $0.category == .cache })
        XCTAssertEqual(Set(result.items.map(\.risk)), [.safe, .rebuildable])
        XCTAssertTrue(result.items.allSatisfy {
            $0.cleanupPolicyScope == .applicationCache
                && $0.cleanupOwnerIdentifier == "com.example.Editor"
        })
        XCTAssertTrue(result.coverage.isComplete)
    }

    func testSkipsSymbolicCacheRoots() async throws {
        let tree = try TemporaryTree(files: ["outside/cache.bin": 64])
        let cacheRoot = tree.url.appending(path: "Library/Caches")
        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: cacheRoot.appending(path: "com.example.Editor"),
            withDestinationURL: tree.url.appending(path: "outside")
        )

        let result = try await ApplicationCacheScanner(
            access: LocalFileSystemAccess()
        ).scan(
            homeDirectory: tree.url,
            applications: [application(
                name: "Editor",
                bundleIdentifier: "com.example.Editor",
                root: tree.url
            )]
        )

        XCTAssertTrue(result.items.isEmpty)
    }

    func testReportsUnreadableCacheRoot() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Caches/com.example.Editor/cache.bin": 64
        ])
        let cacheRoot = tree.url.appending(path: "Library/Caches")

        let result = try await ApplicationCacheScanner(
            access: FixtureFileSystemAccess(unreadable: [cacheRoot])
        ).scan(
            homeDirectory: tree.url,
            applications: [application(
                name: "Editor",
                bundleIdentifier: "com.example.Editor",
                root: tree.url
            )]
        )

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.deniedPaths, [cacheRoot.standardizedFileURL])
    }

    func testFindsOnlyFixedCacheLeavesForExactlyMatchedApplicationSupportRoots() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Application Support/Editor/Cache/cache.bin": 20,
            "Library/Application Support/Editor/Code Cache/code.bin": 21,
            "Library/Application Support/Editor/User Data/Default/Service Worker/CacheStorage/entry": 22,
            "Library/Application Support/Editor/User Data/Profile 1/GPUCache/gpu.bin": 23,
            "Library/Application Support/Editor/Documents/user.txt": 200,
            "Library/Application Support/Unknown/Cache/cache.bin": 201
        ])
        let editor = application(
            name: "Editor",
            bundleIdentifier: "com.example.Editor",
            root: tree.url
        )

        let result = try await ApplicationCacheScanner(
            access: LocalFileSystemAccess()
        ).scan(homeDirectory: tree.url, applications: [editor])

        XCTAssertEqual(result.items.count, 4)
        XCTAssertTrue(result.items.allSatisfy {
            $0.ownerID == editor.id
                && $0.risk == .rebuildable
                && $0.cleanupPolicyRelativePath?.hasPrefix("Library/Application Support/Editor/") == true
        })
        XCTAssertFalse(result.items.contains { $0.url.path.contains("Documents") })
        XCTAssertFalse(result.items.contains { $0.url.path.contains("Unknown") })
    }

    func testFindsKnownNestedCacheRootOnlyForItsExactBundleIdentifier() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Caches/Google/Chrome/cache.bin": 40,
            "Library/Caches/Google/Chrome Canary/cache.bin": 41
        ])
        let chrome = application(
            name: "Google Chrome",
            bundleIdentifier: "com.google.Chrome",
            root: tree.url
        )

        let result = try await ApplicationCacheScanner(
            access: LocalFileSystemAccess()
        ).scan(homeDirectory: tree.url, applications: [chrome])

        XCTAssertTrue(result.items.contains {
            $0.cleanupPolicyRelativePath == "Library/Caches/Google/Chrome"
                && $0.ownerID == chrome.id
                && $0.risk == .safe
        })
        XCTAssertFalse(result.items.contains { $0.url.path.contains("Chrome Canary") })
    }

    private func application(
        name: String,
        bundleIdentifier: String,
        root: URL
    ) -> ApplicationRecord {
        ApplicationRecord(
            name: name,
            bundleIdentifier: bundleIdentifier,
            version: "1",
            url: root.appending(path: "Applications/\(name).app"),
            executableURL: nil,
            allocatedSize: 1
        )
    }
}
