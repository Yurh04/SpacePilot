import XCTest
@testable import SpacePilotCore

final class AIApplicationJoinTests: XCTestCase {
    private func registryApp(
        id: String,
        name: String,
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil,
        version: String? = nil,
        failures: Set<AIToolCoverageFailure> = []
    ) -> AIToolRecord {
        AIToolRecord(
            id: id,
            kind: .application,
            displayName: name,
            owner: .tool(definitionID: name.lowercased()),
            evidence: AIToolEvidence(
                bundleIdentifier: bundleIdentifier,
                applicationURL: applicationURL,
                detectedVersion: version
            ),
            coverageFailures: failures
        )
    }

    private func deepApp(
        name: String,
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil
    ) -> AIApplicationRecord {
        AIApplicationRecord(
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: applicationURL,
            rootURLs: [],
            itemIDs: [],
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .deep
        )
    }

    func testRegistryApplicationCoveredByBundleIdentifierIsExcluded() {
        let deep = deepApp(name: "Claude", bundleIdentifier: "com.anthropic.claude")
        let registry = registryApp(
            id: "app:claude",
            name: "Claude",
            bundleIdentifier: "COM.ANTHROPIC.CLAUDE"
        )

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [deep],
            registryApplications: [registry]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testRegistryApplicationCoveredByApplicationURLIsExcluded() {
        let url = URL(fileURLWithPath: "/Applications/Cursor.app")
        let deep = deepApp(name: "Cursor", applicationURL: url)
        let registry = registryApp(
            id: "app:cursor",
            name: "Cursor",
            applicationURL: URL(fileURLWithPath: "/Applications/Cursor.app/")
        )

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [deep],
            registryApplications: [registry]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testUnmatchedRegistryApplicationIsSurfacedWithEvidence() {
        let deep = deepApp(name: "Claude", bundleIdentifier: "com.anthropic.claude")
        let registry = registryApp(
            id: "app:windsurf",
            name: "Windsurf",
            bundleIdentifier: "com.codeium.windsurf",
            version: "1.2.3",
            failures: [.permissionDenied]
        )

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [deep],
            registryApplications: [registry]
        )

        XCTAssertEqual(result.map(\.id), ["app:windsurf"])
        XCTAssertEqual(result.first?.detectedVersion, "1.2.3")
        XCTAssertEqual(result.first?.coverageFailures, [.permissionDenied])
    }

    func testResultOrderIsIndependentOfInputOrder() {
        let deep = deepApp(name: "Claude", bundleIdentifier: "com.anthropic.claude")
        let alpha = registryApp(id: "app:alpha", name: "Alpha", bundleIdentifier: "io.alpha")
        let beta = registryApp(id: "app:beta", name: "Beta", bundleIdentifier: "io.beta")

        let forward = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [deep],
            registryApplications: [alpha, beta]
        )
        let reversed = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [deep],
            registryApplications: [beta, alpha]
        )

        XCTAssertEqual(forward.map(\.displayName), ["Alpha", "Beta"])
        XCTAssertEqual(forward.map(\.id), reversed.map(\.id))
    }

    func testSameDisplayNameDifferentIdentityAreNotMerged() {
        let alpha = registryApp(id: "app:one", name: "Gemini", bundleIdentifier: "io.one")
        let beta = registryApp(id: "app:two", name: "Gemini", bundleIdentifier: "io.two")

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [],
            registryApplications: [alpha, beta]
        )

        XCTAssertEqual(result.map(\.id), ["app:one", "app:two"])
    }

    func testNonApplicationRecordsAreIgnored() {
        let cli = AIToolRecord(
            id: "cli:codex",
            kind: .cli,
            displayName: "codex",
            owner: .tool(definitionID: "codex")
        )

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [],
            registryApplications: [cli]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testTwoRegistryRecordsSharingBundleIdentifierEmitOneRow() {
        let first = registryApp(id: "app:z", name: "Zed", bundleIdentifier: "dev.zed.Zed")
        let second = registryApp(id: "app:a", name: "Zed Preview", bundleIdentifier: "DEV.ZED.ZED")

        let forward = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [],
            registryApplications: [first, second]
        )
        let reversed = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [],
            registryApplications: [second, first]
        )

        XCTAssertEqual(forward.count, 1)
        // Deterministic survivor regardless of input order (sorted by name then id).
        XCTAssertEqual(forward.map(\.id), reversed.map(\.id))
        XCTAssertEqual(forward.first?.id, "app:z")
    }

    func testTwoRegistryRecordsSharingApplicationURLEmitOneRow() {
        let url = URL(fileURLWithPath: "/Applications/Ollama.app")
        let first = registryApp(id: "app:one", name: "Ollama", applicationURL: url)
        let second = registryApp(
            id: "app:two",
            name: "Ollama Beta",
            applicationURL: URL(fileURLWithPath: "/Applications/Ollama.app/")
        )

        let result = AIApplicationJoin.registryOnlyApplications(
            deepApplications: [],
            registryApplications: [first, second]
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, "app:one")
    }

    func testApplicationCountIsUnionOfDeepAndRegistryOnly() {
        let claudeDeep = deepApp(name: "Claude", bundleIdentifier: "com.anthropic.claude")
        let cursorDeep = deepApp(name: "Cursor", bundleIdentifier: "com.todesktop.cursor")
        // Overlaps Claude (must not double count) plus a genuinely new tool.
        let claudeRegistry = registryApp(id: "r:claude", name: "Claude", bundleIdentifier: "com.anthropic.claude")
        let windsurf = registryApp(id: "r:windsurf", name: "Windsurf", bundleIdentifier: "com.codeium.windsurf")

        let count = AIApplicationJoin.applicationCount(
            deepApplications: [claudeDeep, cursorDeep],
            registryApplications: [claudeRegistry, windsurf]
        )

        // 2 deep + 1 registry-only (windsurf); claude overlap is not counted twice.
        XCTAssertEqual(count, 3)
    }

    func testApplicationCountKeepsDeepAppsWhenRegistryIsEmpty() {
        let deep = deepApp(name: "Claude", bundleIdentifier: "com.anthropic.claude")

        let count = AIApplicationJoin.applicationCount(
            deepApplications: [deep],
            registryApplications: []
        )

        XCTAssertEqual(count, 1)
    }

    func testApplicationCountCountsRegistryOnlyWhenNoDeepApps() {
        let windsurf = registryApp(id: "r:windsurf", name: "Windsurf", bundleIdentifier: "com.codeium.windsurf")

        let count = AIApplicationJoin.applicationCount(
            deepApplications: [],
            registryApplications: [windsurf]
        )

        XCTAssertEqual(count, 1)
    }
}
