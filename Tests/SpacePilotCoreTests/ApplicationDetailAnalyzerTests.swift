import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationDetailAnalyzerTests: XCTestCase {
    func testLinksIndexedCodexDataToMatchingChatGPTApplicationAsShared()
        async throws
    {
        let home = try TemporaryTree(files: [:])
        let built = try TestAppBuilder.make(
            name: "ChatGPT",
            bundleID: "com.openai.codex",
            version: "1.0",
            executableBytes: 16
        )
        let application = ApplicationRecord(
            name: "ChatGPT",
            bundleIdentifier: "com.openai.codex",
            version: "1.0",
            url: built.appURL,
            executableURL: nil,
            allocatedSize: 16
        )
        let codexData = ScannedItem(
            url: home.url.appending(path: ".codex/sessions"),
            logicalSize: 2_000,
            allocatedSize: 2_000,
            category: .conversation,
            risk: .sensitive,
            ownerID: UUID(),
            explanation: "Codex conversation history"
        )
        let codex = AIApplicationRecord(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            applicationURL: application.url,
            rootURLs: [home.url.appending(path: ".codex")],
            itemIDs: [codexData.id],
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .deep
        )
        let analyzer = ApplicationDetailAnalyzer(
            spotlightFinder: SpotlightApplicationCandidateFinder(
                query: FixedSpotlightCandidateQuery(urls: [])
            ),
            knowledgeBase: ApplicationAssociationKnowledgeBase(
                schemaVersion: 1,
                contentVersion: "test",
                rules: []
            )
        )

        let result = try await analyzer.analyze(
            application: application,
            homeDirectory: home.url,
            indexedItems: [codexData],
            indexedAIApplications: [codex]
        )

        let association = try XCTUnwrap(result.associations.first {
            $0.itemID == codexData.id
        })
        XCTAssertEqual(association.evidence, .knownRule)
        XCTAssertEqual(association.confidence, .high)
        XCTAssertEqual(association.ownership, .shared)
        XCTAssertEqual(association.risk, .sensitive)
        XCTAssertFalse(result.items.contains { $0.id == codexData.id })
    }

    func testUsesSpotlightForDeepCandidateWithoutRescanningApplicationList()
        async throws
    {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Vendor/Nested/com.example.Example/state.db": 73
        ])
        let applications = home.url.appending(
            path: "Applications",
            directoryHint: .isDirectory
        )
        let built = try TestAppBuilder.make(
            in: applications,
            name: "Example",
            bundleID: "com.example.Example",
            version: "1.0",
            executableBytes: 16
        )
        let deepCandidate = home.url.appending(
            path: "Library/Application Support/Vendor/Nested/com.example.Example",
            directoryHint: .isDirectory
        )
        let application = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.Example",
            version: "1.0",
            url: built.appURL,
            executableURL: built.appURL.appending(path: "Contents/MacOS/Example"),
            allocatedSize: 16
        )
        let analyzer = ApplicationDetailAnalyzer(
            spotlightFinder: SpotlightApplicationCandidateFinder(
                query: FixedSpotlightCandidateQuery(urls: [deepCandidate]),
                includesFuzzyNameMatch: false
            ),
            knowledgeBase: ApplicationAssociationKnowledgeBase(
                schemaVersion: 1,
                contentVersion: "test",
                rules: []
            )
        )

        let result = try await analyzer.analyze(
            application: application,
            homeDirectory: home.url
        )

        let item = try XCTUnwrap(result.items.first {
            $0.url.standardizedFileURL == deepCandidate.standardizedFileURL
        })
        let association = try XCTUnwrap(result.associations.first {
            $0.itemID == item.id
        })
        XCTAssertEqual(association.evidence, .exactBundleIdentifier)
        XCTAssertEqual(association.confidence, .high)
        XCTAssertEqual(association.ownership, .owned)
    }

    func testFuzzySpotlightCandidateIsPossibleAndSensitive() async throws {
        let home = try TemporaryTree(files: [
            "Library/Application Support/Example Legacy/state.db": 31
        ])
        let built = try TestAppBuilder.make(
            name: "Example",
            bundleID: "com.example.Example",
            version: "1.0",
            executableBytes: 16
        )
        let candidate = home.url.appending(
            path: "Library/Application Support/Example Legacy",
            directoryHint: .isDirectory
        )
        let application = ApplicationRecord(
            name: "Example",
            bundleIdentifier: "com.example.Example",
            version: "1.0",
            url: built.appURL,
            executableURL: nil,
            allocatedSize: 16
        )
        let analyzer = ApplicationDetailAnalyzer(
            spotlightFinder: SpotlightApplicationCandidateFinder(
                query: NameOnlySpotlightCandidateQuery(url: candidate)
            ),
            knowledgeBase: ApplicationAssociationKnowledgeBase(
                schemaVersion: 1,
                contentVersion: "test",
                rules: []
            )
        )

        let result = try await analyzer.analyze(
            application: application,
            homeDirectory: home.url
        )
        let item = try XCTUnwrap(result.items.first {
            $0.url.standardizedFileURL == candidate.standardizedFileURL
        })
        let association = try XCTUnwrap(result.associations.first {
            $0.itemID == item.id
        })
        XCTAssertEqual(item.risk, .sensitive)
        XCTAssertEqual(association.confidence, .low)
        XCTAssertEqual(association.ownership, .possible)
    }
}

private struct FixedSpotlightCandidateQuery:
    SpotlightApplicationCandidateQuerying
{
    let urls: [URL]

    func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL] {
        Array(urls.prefix(limit))
    }
}

private struct NameOnlySpotlightCandidateQuery:
    SpotlightApplicationCandidateQuerying
{
    let url: URL

    func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL] {
        guard case .nameFragment = query, limit > 0 else { return [] }
        return [url]
    }
}
