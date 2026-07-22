import XCTest
@testable import SpacePilotCore

final class AIAdapterTests: XCTestCase {
    func testCodexClassifiesKnownAssetsWithoutReadingContents() async throws {
        let tree = try TemporaryTree(files: [
            ".codex/sessions/session.jsonl": 120,
            ".codex/logs/codex.log": 80,
            ".codex/cache/index.bin": 200,
            ".codex/config.toml": 20
        ])

        let result = try await CodexAdapter().scan(homeDirectory: tree.url)

        XCTAssertEqual(result.itemsByCategory[.conversation]?.count, 1)
        XCTAssertEqual(result.itemsByCategory[.log]?.count, 1)
        XCTAssertEqual(result.itemsByCategory[.cache]?.count, 1)
        XCTAssertEqual(result.itemsByCategory[.aiData]?.count, 1)
        XCTAssertTrue(result.indexedContentBodies.isEmpty)
    }

    func testClaudeClassifiesProjectsAsConversationData() async throws {
        let tree = try TemporaryTree(files: [
            ".claude/projects/project-a/transcript.jsonl": 64,
            ".claude/debug/session.log": 32,
            ".claude/settings.json": 16
        ])

        let result = try await ClaudeAdapter().scan(homeDirectory: tree.url)

        XCTAssertEqual(result.application.name, "Claude")
        XCTAssertEqual(result.itemsByCategory[.conversation]?.count, 1)
        XCTAssertEqual(result.itemsByCategory[.log]?.count, 1)
        XCTAssertEqual(result.itemsByCategory[.aiData]?.count, 1)
    }

    func testUnknownCodexAssetIsSensitiveAndNotRecommendedForCleanup() async throws {
        let tree = try TemporaryTree(files: [
            ".codex/mystery/private.dat": 48
        ])

        let result = try await CodexAdapter().scan(homeDirectory: tree.url)
        let item = try XCTUnwrap(result.items.first)

        XCTAssertEqual(item.category, .unclassified)
        XCTAssertEqual(item.risk, .sensitive)
        XCTAssertFalse(result.cleanupRecommendedItemIDs.contains(item.id))
    }

    func testBasicScannerReportsOnlyConfiguredFootprintRoots() async throws {
        let tree = try TemporaryTree(files: [
            "Library/Application Support/ChatGPT/state.db": 50,
            "Library/Caches/com.openai.chat/cache.bin": 25,
            "Documents/ChatGPT Notes/private.txt": 100
        ])

        let result = try await BasicAIApplicationScanner().scan(
            name: "ChatGPT",
            bundleIdentifier: "com.openai.chat",
            homeDirectory: tree.url,
            relativeRoots: [
                "Library/Application Support/ChatGPT",
                "Library/Caches/com.openai.chat"
            ]
        )

        XCTAssertEqual(result.application.supportLevel, .basic)
        XCTAssertEqual(result.application.rootURLs.count, 2)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertFalse(result.items.contains { $0.url.path.contains("Documents") })
    }
}
