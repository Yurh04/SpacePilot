import Foundation
import SpacePilotCore
import XCTest

final class AIUpdateCheckingTests: XCTestCase {
    func testSemVerComparisonCoversPrereleaseBuildMetadataAndInvalidInputs() {
        XCTAssertEqual(SemVerComparator.compare("1.0.0", "1.0.1"), .orderedAscending)
        XCTAssertEqual(SemVerComparator.compare("v1.2.3", "1.2.3"), .orderedSame)
        XCTAssertEqual(SemVerComparator.compare("1.0.0-beta", "1.0.0"), .orderedAscending)
        XCTAssertEqual(SemVerComparator.compare("1.0.0-beta.2", "1.0.0-beta.11"), .orderedAscending)
        XCTAssertEqual(SemVerComparator.compare("1.0.0+build.1", "1.0.0+build.2"), .orderedSame)
        XCTAssertNil(SemVerComparator.compare("1.0", "1.0.1"))
        XCTAssertNil(SemVerComparator.compare(String(repeating: "1", count: 129), "1.0.0"))
        XCTAssertEqual(SemVerComparator.compare("1.0.0", "1.1.0-beta"), .orderedDescending)
        XCTAssertEqual(SemVerComparator.compare("1.0.0", "1.1.0-beta", allowsPrerelease: true), .orderedAscending)
    }

    func testRequestValidationRejectsUnsafeURLsAndAcceptsFixedProviderPaths() throws {
        let npm = UpdateMetadataRequest.npm(package: "@openai/codex")
        let pypi = UpdateMetadataRequest.pypi(package: "aider-chat")
        XCTAssertTrue(UpdateRequestValidator.validate(try XCTUnwrap(npm.url), for: npm))
        XCTAssertTrue(UpdateRequestValidator.validate(try XCTUnwrap(pypi.url), for: pypi))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "http://registry.npmjs.org/@openai/codex")!, for: npm))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "https://user@registry.npmjs.org/@openai/codex")!, for: npm))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "https://registry.npmjs.org:444/@openai/codex")!, for: npm))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "https://127.0.0.1/@openai/codex")!, for: npm))
        XCTAssertFalse(UpdateRequestValidator.validate(URL(string: "https://registry.npmjs.org/@openai/../codex")!, for: npm))
        XCTAssertFalse(UpdateRequestValidator.isAllowedRedirect(
            from: URL(string: "https://registry.npmjs.org/@openai/codex")!,
            to: URL(string: "https://evil.example/@openai/codex")!
        ))
    }

    func testParsesProviderResponses() throws {
        let npm = Data(#"{"dist-tags":{"latest":"1.2.3"}}"#.utf8)
        let pypi = Data(#"{"info":{"version":"2.0.0"}}"#.utf8)
        XCTAssertEqual(try LocalUpdateMetadataFetcher.parse(npm, request: .npm(package: "@openai/codex")).latestVersion, "1.2.3")
        XCTAssertEqual(try LocalUpdateMetadataFetcher.parse(pypi, request: .pypi(package: "aider-chat")).latestVersion, "2.0.0")
        XCTAssertThrowsError(try LocalUpdateMetadataFetcher.parse(Data(#"{}"#.utf8), request: .npm(package: "x")))
    }

    func testCheckerUsesStableKeysDeduplicatesProviderAndFailsUnknownProviderClosed() async {
        let fetcher = FakeUpdateFetcher(responses: ["npm:@openai/codex": .success(.init(latestVersion: "1.1.0"))])
        let checker = AIUpdateChecker(fetcher: fetcher)
        let codexA = asset(path: "/bin/codex-a", version: "1.0.0", providerID: "npm")
        let codexB = asset(path: "/bin/codex-b", version: "1.1.0", providerID: "npm")
        let unknown = asset(path: "/bin/unknown", version: "1.0.0", providerID: "custom")

        let results = await checker.check([codexA, codexB, unknown])

        XCTAssertEqual(results.first { $0.assetKey == codexA.key }?.status, .updateAvailable)
        XCTAssertEqual(results.first { $0.assetKey == codexB.key }?.status, .upToDate)
        XCTAssertEqual(results.first { $0.assetKey == unknown.key }?.failure, .unknownProvider)
        let requests = await fetcher.recordedRequests()
        XCTAssertEqual(requests, [.npm(package: "@openai/codex")])
    }

    func testEvidenceResolverReportsConflictsAtHighestConfidence() {
        let state = VersionEvidenceResolver.resolve([
            VersionEvidence(version: "1.0.0", source: .cliProbe, confidence: .high),
            VersionEvidence(version: "2.0.0", source: .packageReceipt, confidence: .high),
            VersionEvidence(version: "0.1.0", source: .pluginManifest, confidence: .medium)
        ])
        guard case .conflict(let evidences) = state else {
            return XCTFail("Expected conflict")
        }
        XCTAssertEqual(Set(evidences.map(\.version)), ["1.0.0", "2.0.0"])
    }

    func testAssetBuilderKeepsUnsupportedAssetsAndTrustedVersionsSeparate() {
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [ApplicationRecord(
                name: "App",
                bundleIdentifier: "com.example.app",
                version: "1.0.0",
                url: URL(fileURLWithPath: "/Applications/App.app"),
                executableURL: nil,
                allocatedSize: 1
            )],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        let cli = AIToolRecord(
            id: "cli:codex:/bin/codex",
            kind: .cli,
            displayName: "Codex",
            owner: .tool(definitionID: "codex"),
            evidence: AIToolEvidence(executableURL: URL(fileURLWithPath: "/bin/codex"), detectedVersion: "1.0.0")
        )
        let inventory = AIUpdateAssetBuilder.inventory(
            snapshot: snapshot,
            managementProjection: AIManagementProjection(records: [cli]),
            projectSkills: [],
            projectPlugins: [],
            definitions: [AIToolDefinition(
                id: "codex",
                displayName: "Codex",
                updateCapability: UpdateCapability(providerID: "npm", providerKind: .npmRegistry, packageIdentifier: "@openai/codex")
            )]
        )
        XCTAssertEqual(inventory.assets.count, 2)
        XCTAssertEqual(inventory.assets.first { $0.key.kind == .cli }?.localVersion.selectedVersion, "1.0.0")
        XCTAssertEqual(inventory.assets.first { $0.key.kind == .cli }?.capability?.packageIdentifier, "@openai/codex")
        XCTAssertEqual(inventory.unsupportedResults.map(\.status), [.unsupported])
    }

    private func asset(path: String, version: String, providerID: String) -> AIUpdateAsset {
        AIUpdateAsset(
            key: AIUpdateAssetKey(kind: .cli, owner: .tool(definitionID: "codex"), canonicalLocation: path),
            displayName: path,
            definitionID: "codex",
            localVersion: .resolved(VersionEvidence(version: version, source: .cliProbe, confidence: .high)),
            capability: UpdateCapability(providerID: providerID, providerKind: .npmRegistry, packageIdentifier: "@openai/codex")
        )
    }

    func testSelectionPlanClassifiesSupportedUnsupportedAndStatusDeterministically() {
        let supported = asset(path: "/bin/codex", version: "1.0.0", providerID: "npm")
        let unsupportedAsset = AIUpdateAsset(
            key: AIUpdateAssetKey(kind: .plugin, owner: .tool(definitionID: "codex"), canonicalLocation: "/p/plugin"),
            displayName: "Plugin",
            definitionID: "codex",
            localVersion: .unknown,
            capability: nil
        )
        let results: [AIUpdateAssetKey: UpdateCheckResult] = [
            supported.key: UpdateCheckResult(
                assetKey: supported.key,
                displayName: "Codex",
                localVersion: supported.localVersion,
                latestVersion: "1.2.0",
                status: .updateAvailable,
                checkedAt: .now,
                failure: nil
            )
        ]

        let plan = AIUpdateSelectionPlan(
            selectedKeys: [supported.key, unsupportedAsset.key],
            assets: [unsupportedAsset, supported],
            results: results
        )

        XCTAssertEqual(plan.selected.map(\.key), [supported.key, unsupportedAsset.key].sorted())
        XCTAssertEqual(plan.supported.map(\.key), [supported.key])
        XCTAssertEqual(plan.unsupported.map(\.key), [unsupportedAsset.key])
        XCTAssertEqual(plan.updateAvailable.map(\.key), [supported.key])
        XCTAssertTrue(plan.alreadyLatest.isEmpty)
        XCTAssertEqual(plan.checkableKeys, [supported.key])
        XCTAssertEqual(plan.supported.first?.latestVersion, "1.2.0")
    }

    func testSelectionPlanIgnoresUnknownKeysAndMarksConflicts() {
        let conflictAsset = AIUpdateAsset(
            key: AIUpdateAssetKey(kind: .cli, owner: .tool(definitionID: "codex"), canonicalLocation: "/bin/codex"),
            displayName: "Codex",
            definitionID: "codex",
            localVersion: .conflict([
                VersionEvidence(version: "1.0.0", source: .cliProbe, confidence: .high),
                VersionEvidence(version: "2.0.0", source: .packageReceipt, confidence: .high)
            ]),
            capability: UpdateCapability(providerID: "npm", providerKind: .npmRegistry, packageIdentifier: "@openai/codex")
        )
        let ghostKey = AIUpdateAssetKey(kind: .cli, owner: .unknown, canonicalLocation: "/bin/ghost")

        let plan = AIUpdateSelectionPlan(
            selectedKeys: [conflictAsset.key, ghostKey],
            assets: [conflictAsset],
            results: [:]
        )

        XCTAssertEqual(plan.selected.map(\.key), [conflictAsset.key])
        XCTAssertEqual(plan.conflict.map(\.key), [conflictAsset.key])
        XCTAssertEqual(plan.supported.first?.status, .unknown)
        XCTAssertNil(plan.currentVersionGhostLookup(ghostKey))
    }
}

private extension AIUpdateSelectionPlan {
    // Test helper: confirm a ghost key never appears in any bucket.
    func currentVersionGhostLookup(_ key: AIUpdateAssetKey) -> String? {
        selected.first { $0.key == key }?.currentVersion
    }
}


private actor FakeUpdateFetcher: UpdateMetadataFetching {
    private let responses: [String: Result<UpdateMetadataResponse, UpdateCheckFailure>]
    private(set) var requests: [UpdateMetadataRequest] = []

    init(responses: [String: Result<UpdateMetadataResponse, UpdateCheckFailure>]) {
        self.responses = responses
    }

    func fetch(_ request: UpdateMetadataRequest) async throws -> UpdateMetadataResponse {
        requests.append(request)
        switch responses[request.providerKey] ?? .failure(.invalidResponse) {
        case .success(let response): return response
        case .failure(let failure): throw failure
        }
    }

    func recordedRequests() -> [UpdateMetadataRequest] { requests }
}
