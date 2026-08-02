import Foundation
import XCTest
@testable import SpacePilotCore

final class SpotlightApplicationCandidateDiscoveryTests: XCTestCase {
    func testExactIdentifiersPrecedeLowConfidenceNameMatch() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let mainURL = home.appending(path: "Library/Preferences/com.example.Editor.plist")
        let helperURL = home.appending(path: "Library/Caches/com.example.Editor.Helper")
        let groupURL = home.appending(path: "Library/Group Containers/TEAM.editor")
        let fuzzyURL = home.appending(path: "Library/Logs/Editor-old.log")
        let query = StubSpotlightCandidateQuery(results: [
            .bundleIdentifier("com.example.Editor"): [mainURL],
            .bundleIdentifier("com.example.Editor.Helper"): [helperURL],
            .applicationGroup("TEAM.editor"): [groupURL],
            .nameFragment("Editor"): [fuzzyURL]
        ])
        let application = makeApplication(name: "Editor", bundleID: "com.example.Editor")
        let identity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: "com.example.Editor",
            componentBundleIdentifiers: ["com.example.Editor.Helper"],
            teamIdentifier: "TEAM",
            applicationGroups: ["TEAM.editor"]
        )

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: identity,
            homeDirectory: home
        )

        XCTAssertEqual(candidates.map(\.url), [mainURL, helperURL, groupURL, fuzzyURL])
        XCTAssertEqual(candidates.map(\.confidence), [.high, .high, .high, .low])
        XCTAssertEqual(candidates.map(\.evidence), [
            .exactBundleIdentifier,
            .signedHelperRelationship,
            .exactContainerIdentifier,
            .vendorAndNameMatch
        ])
    }

    func testDeduplicatesAndRetainsHigherPriorityEvidence() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let duplicate = home.appending(path: "Library/Caches/com.example.Editor")
        let query = StubSpotlightCandidateQuery(results: [
            .bundleIdentifier("com.example.Editor"): [duplicate, duplicate],
            .nameFragment("Editor"): [duplicate]
        ])
        let application = makeApplication(name: "Editor", bundleID: "com.example.Editor")

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )

        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].confidence, .high)
        XCTAssertEqual(candidates[0].evidence, .exactBundleIdentifier)
    }

    func testRejectsPathsOutsideKnownHomeArtifactRoots() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let allowed = home.appending(path: "Library/Caches/com.example.Editor")
        let personalFile = home.appending(path: "Documents/Editor manuscript.txt")
        let otherUser = URL(fileURLWithPath: "/Users/other/Library/Caches/Editor")
        let system = URL(fileURLWithPath: "/Library/Caches/Editor")
        let remote = URL(string: "file://server/Users/tester/Library/Caches/Editor")!
        let query = StubSpotlightCandidateQuery(results: [
            .bundleIdentifier("com.example.Editor"): [
                personalFile, otherUser, allowed, system, remote
            ]
        ])
        let application = makeApplication(name: "Editor", bundleID: "com.example.Editor")

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )

        XCTAssertEqual(candidates.map(\.url), [allowed])
    }

    func testRejectsMetadataMirroredInsideAnotherApplicationsBundleDirectory()
        async throws
    {
        let home = URL(fileURLWithPath: "/Users/tester")
        let mirrored = home.appending(
            path: "Library/Application Support/com.vendor.Cleaner/AppCatalog/com.example.Editor.plist"
        )
        let relatedVendor = home.appending(
            path: "Library/Application Support/com.example.Updater/com.example.Editor.plist"
        )
        let direct = home.appending(
            path: "Library/Preferences/com.example.Editor.plist"
        )
        let query = StubSpotlightCandidateQuery(results: [
            .bundleIdentifier("com.example.Editor"): [
                mirrored, relatedVendor, direct
            ]
        ])
        let application = makeApplication(
            name: "Editor",
            bundleID: "com.example.Editor"
        )

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )

        XCTAssertEqual(candidates.map(\.url), [relatedVendor, direct])
    }

    func testAppliesHardCandidateLimitAcrossQueries() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let mainResults = (0..<4).map {
            home.appending(path: "Library/Caches/com.example.Editor/\($0)")
        }
        let fuzzyResults = (4..<10).map {
            home.appending(path: "Library/Caches/Editor/\($0)")
        }
        let query = RecordingSpotlightCandidateQuery(results: [
            .bundleIdentifier("com.example.Editor"): mainResults,
            .nameFragment("Editor"): fuzzyResults
        ])
        let application = makeApplication(name: "Editor", bundleID: "com.example.Editor")

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query,
            maximumCandidates: 3
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )
        let calls = await query.recordedCalls()

        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].limit, 3)
    }

    func testShortNameDoesNotProduceFuzzyQuery() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let query = RecordingSpotlightCandidateQuery(results: [:])
        let application = makeApplication(name: "AI", bundleID: nil)

        let candidates = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )
        let calls = await query.recordedCalls()

        XCTAssertTrue(candidates.isEmpty)
        XCTAssertTrue(calls.isEmpty)
    }

    func testAmbiguousApplicationNameDoesNotProduceFuzzyQuery() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let query = RecordingSpotlightCandidateQuery(results: [:])
        let application = makeApplication(
            name: "Code",
            bundleID: "com.microsoft.VSCode"
        )

        _ = try await SpotlightApplicationCandidateFinder(
            query: query
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )
        let calls = await query.recordedCalls()

        XCTAssertEqual(calls.map(\.query), [
            .bundleIdentifier("com.microsoft.VSCode")
        ])
    }

    func testCanDisableFuzzyNameMatching() async throws {
        let home = URL(fileURLWithPath: "/Users/tester")
        let query = RecordingSpotlightCandidateQuery(results: [:])
        let application = makeApplication(name: "Editor", bundleID: "com.example.Editor")

        _ = try await SpotlightApplicationCandidateFinder(
            query: query,
            includesFuzzyNameMatch: false
        ).candidates(
            for: application,
            identity: makeIdentity(for: application),
            homeDirectory: home
        )
        let calls = await query.recordedCalls()

        XCTAssertEqual(calls.map(\.query), [
            .bundleIdentifier("com.example.Editor")
        ])
    }

    private func makeApplication(
        name: String,
        bundleID: String?
    ) -> ApplicationRecord {
        ApplicationRecord(
            name: name,
            bundleIdentifier: bundleID,
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            executableURL: nil,
            allocatedSize: 0
        )
    }

    private func makeIdentity(
        for application: ApplicationRecord
    ) -> ApplicationIdentity {
        ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: [],
            teamIdentifier: nil,
            applicationGroups: []
        )
    }
}

private struct StubSpotlightCandidateQuery:
    SpotlightApplicationCandidateQuerying
{
    let results: [SpotlightApplicationCandidateQuery: [URL]]

    func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL] {
        Array((results[query] ?? []).prefix(limit))
    }
}

private actor RecordingSpotlightCandidateQuery:
    SpotlightApplicationCandidateQuerying
{
    struct Call: Sendable {
        let query: SpotlightApplicationCandidateQuery
        let scopes: [URL]
        let limit: Int
    }

    private let results: [SpotlightApplicationCandidateQuery: [URL]]
    private var calls: [Call] = []

    init(results: [SpotlightApplicationCandidateQuery: [URL]]) {
        self.results = results
    }

    func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL] {
        calls.append(Call(query: query, scopes: scopes, limit: limit))
        return Array((results[query] ?? []).prefix(limit))
    }

    func recordedCalls() -> [Call] {
        calls
    }
}
