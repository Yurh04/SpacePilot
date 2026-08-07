import Foundation
import XCTest
@testable import SpacePilotCore

final class SnapshotAIApplicationLocatorTests: XCTestCase {
    func testResolvesAIApplicationURLByBundleIdentifier() {
        let url = URL(fileURLWithPath: "/Applications/Claude.app")
        let snapshot = makeSnapshot(aiApplications: [
            aiApplication(bundleID: "com.anthropic.claudefordesktop", url: url)
        ])
        let locator = SnapshotAIApplicationLocator(snapshot: snapshot)
        XCTAssertEqual(
            locator.applicationURL(forBundleIdentifier: "com.anthropic.claudefordesktop"),
            url
        )
    }

    func testReturnsNilForUnknownBundleIdentifier() {
        let snapshot = makeSnapshot(aiApplications: [
            aiApplication(bundleID: "com.openai.codex", url: URL(fileURLWithPath: "/Applications/Codex.app"))
        ])
        let locator = SnapshotAIApplicationLocator(snapshot: snapshot)
        XCTAssertNil(locator.applicationURL(forBundleIdentifier: "com.unknown.tool"))
    }

    func testAIApplicationURLTakesPriorityOverGeneralApplication() {
        let aiURL = URL(fileURLWithPath: "/Applications/AI/Codex.app")
        let appURL = URL(fileURLWithPath: "/Applications/Codex.app")
        let snapshot = makeSnapshot(
            applications: [application(bundleID: "com.openai.codex", url: appURL)],
            aiApplications: [aiApplication(bundleID: "com.openai.codex", url: aiURL)]
        )
        let locator = SnapshotAIApplicationLocator(snapshot: snapshot)
        XCTAssertEqual(
            locator.applicationURL(forBundleIdentifier: "com.openai.codex"),
            aiURL
        )
    }

    func testFallsBackToGeneralApplicationWhenNoAIApplicationURL() {
        let appURL = URL(fileURLWithPath: "/Applications/Cursor.app")
        let snapshot = makeSnapshot(
            applications: [application(bundleID: "com.todesktop.x", url: appURL)],
            aiApplications: [aiApplication(bundleID: "com.todesktop.x", url: nil)]
        )
        let locator = SnapshotAIApplicationLocator(snapshot: snapshot)
        XCTAssertEqual(
            locator.applicationURL(forBundleIdentifier: "com.todesktop.x"),
            appURL
        )
    }

    func testDeterministicPickIsIndependentOfOrdering() {
        let first = URL(fileURLWithPath: "/Applications/A-Codex.app")
        let second = URL(fileURLWithPath: "/Applications/Z-Codex.app")
        let forward = SnapshotAIApplicationLocator(snapshot: makeSnapshot(applications: [
            application(bundleID: "com.openai.codex", url: second),
            application(bundleID: "com.openai.codex", url: first)
        ]))
        let reverse = SnapshotAIApplicationLocator(snapshot: makeSnapshot(applications: [
            application(bundleID: "com.openai.codex", url: first),
            application(bundleID: "com.openai.codex", url: second)
        ]))
        XCTAssertEqual(
            forward.applicationURL(forBundleIdentifier: "com.openai.codex"),
            first
        )
        XCTAssertEqual(
            forward.applicationURL(forBundleIdentifier: "com.openai.codex"),
            reverse.applicationURL(forBundleIdentifier: "com.openai.codex")
        )
    }

    // MARK: - Fixtures

    private func makeSnapshot(
        applications: [ApplicationRecord] = [],
        aiApplications: [AIApplicationRecord] = []
    ) -> ScanSnapshot {
        ScanSnapshot(
            completedAt: Date(timeIntervalSince1970: 0),
            volume: nil,
            items: [],
            applications: applications,
            aiApplications: aiApplications,
            plugins: [],
            skills: [],
            coverage: .complete
        )
    }

    private func application(bundleID: String?, url: URL) -> ApplicationRecord {
        ApplicationRecord(
            name: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleID,
            version: nil,
            url: url,
            executableURL: nil,
            allocatedSize: 0
        )
    }

    private func aiApplication(bundleID: String?, url: URL?) -> AIApplicationRecord {
        AIApplicationRecord(
            name: bundleID ?? "AI",
            bundleIdentifier: bundleID,
            applicationURL: url,
            rootURLs: [],
            itemIDs: [],
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .basic
        )
    }
}
