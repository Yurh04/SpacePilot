import Foundation
@testable import SpacePilotCore
import XCTest

/// Tests for stage 5B: the user-confirmed manual update execution path. Every
/// test uses a fake process runner, a fake manager locator, and a fake version
/// probe, so NO real update ever runs against the machine.
final class AIUpdateExecutionTests: XCTestCase {
    // MARK: - Fixtures

    private func key(kind: AIUpdateAssetKind = .cli, definitionID: String = "codex", path: String) -> AIUpdateAssetKey {
        AIUpdateAssetKey(kind: kind, owner: .tool(definitionID: definitionID), canonicalLocation: path)
    }

    private func asset(
        kind: AIUpdateAssetKind = .cli,
        definitionID: String = "codex",
        path: String,
        version: String?,
        capable: Bool = true
    ) -> AIUpdateAsset {
        let capability = capable
            ? UpdateCapability(providerID: "npm", providerKind: .npmRegistry, packageIdentifier: "@openai/codex")
            : nil
        let localVersion: LocalVersionState = version.map {
            .resolved(VersionEvidence(version: $0, source: .cliProbe, confidence: .high))
        } ?? .unknown
        return AIUpdateAsset(
            key: key(kind: kind, definitionID: definitionID, path: path),
            displayName: path,
            definitionID: definitionID,
            localVersion: localVersion,
            capability: capability
        )
    }

    private func result(
        for asset: AIUpdateAsset,
        latest: String?,
        status: UpdateStatus
    ) -> UpdateCheckResult {
        UpdateCheckResult(
            assetKey: asset.key,
            displayName: asset.displayName,
            localVersion: asset.localVersion,
            latestVersion: latest,
            status: status,
            checkedAt: .now,
            failure: nil
        )
    }

    // MARK: - UpdateExecutionPlan classification

    func testPlanOnlyPromotesCheckedUpdateAvailableWithCapabilityAndValidVersion() {
        let updatable = asset(path: "/bin/codex", version: "1.0.0")
        let latest = asset(kind: .cli, definitionID: "aiden", path: "/bin/aiden", version: "2.0.0")
        let notChecked = asset(kind: .cli, definitionID: "aider", path: "/bin/aider", version: "3.0.0")
        let noCapability = asset(kind: .plugin, path: "/p/plugin", version: nil, capable: false)

        let capabilities: [AIUpdateAssetKey: UpdateExecutionCapability] = [
            updatable.key: UpdateExecutionCapability(manager: .npm, packageIdentifier: "@openai/codex"),
            latest.key: UpdateExecutionCapability(manager: .pnpm, packageIdentifier: "@aiden-cli/core"),
            notChecked.key: UpdateExecutionCapability(manager: .pipx, packageIdentifier: "aider-chat")
        ]
        let results: [AIUpdateAssetKey: UpdateCheckResult] = [
            updatable.key: result(for: updatable, latest: "1.2.0", status: .updateAvailable),
            latest.key: result(for: latest, latest: "2.0.0", status: .upToDate)
        ]

        let plan = UpdateExecutionPlan(
            selectedKeys: [updatable.key, latest.key, notChecked.key, noCapability.key],
            assets: [updatable, latest, notChecked, noCapability],
            executionCapabilities: capabilities,
            results: results
        )

        XCTAssertEqual(plan.executable.map(\.key), [updatable.key])
        XCTAssertEqual(plan.executable.first?.targetVersion, "1.2.0")
        XCTAssertEqual(plan.executable.first?.manager, .npm)
        XCTAssertTrue(plan.hasExecutable)

        let skipReasons = Dictionary(uniqueKeysWithValues: plan.skipped.map { ($0.key, $0.reason) })
        XCTAssertEqual(skipReasons[latest.key], .alreadyLatest)
        XCTAssertEqual(skipReasons[notChecked.key], .notChecked)
        XCTAssertEqual(skipReasons[noCapability.key], .unsupported)
    }

    func testPlanSkipsInvalidTargetVersionAndDeduplicatesByPackage() {
        let invalid = asset(path: "/bin/codex", version: "1.0.0")
        let aliasA = asset(path: "/bin/codex-alias-a", version: "1.0.0")
        let aliasB = asset(path: "/bin/codex-alias-b", version: "1.0.0")

        let capability = UpdateExecutionCapability(manager: .npm, packageIdentifier: "@openai/codex")
        let capabilities: [AIUpdateAssetKey: UpdateExecutionCapability] = [
            invalid.key: capability,
            aliasA.key: capability,
            aliasB.key: capability
        ]

        // invalid: latest is not SemVer. aliasA/aliasB: same package, both updatable.
        let results: [AIUpdateAssetKey: UpdateCheckResult] = [
            aliasA.key: result(for: aliasA, latest: "1.2.0", status: .updateAvailable),
            aliasB.key: result(for: aliasB, latest: "1.2.0", status: .updateAvailable)
        ]

        let invalidResults: [AIUpdateAssetKey: UpdateCheckResult] = [
            invalid.key: result(for: invalid, latest: "not-a-version", status: .updateAvailable)
        ]

        let dedupePlan = UpdateExecutionPlan(
            selectedKeys: [aliasA.key, aliasB.key],
            assets: [aliasA, aliasB],
            executionCapabilities: capabilities,
            results: results
        )
        // Same (manager, package) is only installed once.
        XCTAssertEqual(dedupePlan.executable.count, 1)

        let invalidPlan = UpdateExecutionPlan(
            selectedKeys: [invalid.key],
            assets: [invalid],
            executionCapabilities: capabilities,
            results: invalidResults
        )
        XCTAssertTrue(invalidPlan.executable.isEmpty)
        XCTAssertEqual(invalidPlan.skipped.first?.reason, .invalidTargetVersion)
    }

    func testPlanIsDeterministicRegardlessOfSelectionOrder() {
        let a = asset(path: "/bin/a", version: "1.0.0")
        let b = asset(kind: .cli, definitionID: "aiden", path: "/bin/b", version: "1.0.0")
        let capabilities: [AIUpdateAssetKey: UpdateExecutionCapability] = [
            a.key: UpdateExecutionCapability(manager: .npm, packageIdentifier: "@openai/codex"),
            b.key: UpdateExecutionCapability(manager: .pnpm, packageIdentifier: "@aiden-cli/core")
        ]
        let results: [AIUpdateAssetKey: UpdateCheckResult] = [
            a.key: result(for: a, latest: "1.1.0", status: .updateAvailable),
            b.key: result(for: b, latest: "1.1.0", status: .updateAvailable)
        ]

        let plan1 = UpdateExecutionPlan(selectedKeys: [a.key, b.key], assets: [a, b], executionCapabilities: capabilities, results: results)
        let plan2 = UpdateExecutionPlan(selectedKeys: [b.key, a.key], assets: [b, a], executionCapabilities: capabilities, results: results)
        XCTAssertEqual(plan1.executable.map(\.key), plan2.executable.map(\.key))
    }

    // MARK: - Argument templates

    func testArgumentTemplatesAreFixedPerManager() {
        XCTAssertEqual(
            AIUpdateExecutor.arguments(manager: .npm, packageIdentifier: "@openai/codex", targetVersion: "1.2.3"),
            ["install", "--global", "@openai/codex@1.2.3"]
        )
        XCTAssertEqual(
            AIUpdateExecutor.arguments(manager: .pnpm, packageIdentifier: "@aiden-cli/core", targetVersion: "2.0.0"),
            ["add", "--global", "@aiden-cli/core@2.0.0"]
        )
        XCTAssertEqual(
            AIUpdateExecutor.arguments(manager: .pipx, packageIdentifier: "aider-chat", targetVersion: "3.1.0"),
            ["install", "--force", "aider-chat==3.1.0"]
        )
    }

    // MARK: - Executor outcomes

    func testExecutorReportsSuccessOnlyWhenReprobeMatchesTarget() async {
        let item = UpdateExecutionPlan.Item(
            key: key(path: "/bin/codex"),
            displayName: "Codex",
            manager: .npm,
            packageIdentifier: "@openai/codex",
            currentVersion: "1.0.0",
            targetVersion: "1.2.0",
            managerDisplayName: "npm"
        )
        let plan = UpdateExecutionPlan(executable: [item], skipped: [])

        let runner = FakeProcessRunner(result: .success(FakeProcessRunner.output(status: 0)))
        let locator = FakeManagerLocator(paths: [.npm: URL(fileURLWithPath: "/opt/homebrew/bin/npm")])
        let probe = FakeVersionProbe(version: "1.2.0")
        let executor = AIUpdateExecutor(runner: runner, managerLocator: locator, versionProbe: probe)

        let results = await executor.execute(plan)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.outcome, .succeeded(installedVersion: "1.2.0"))
        let runs = await runner.recordedRuns()
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.arguments, ["install", "--global", "@openai/codex@1.2.0"])
    }

    func testExecutorReportsVersionMismatchWhenReprobeDiffers() async {
        let item = UpdateExecutionPlan.Item(
            key: key(path: "/bin/codex"), displayName: "Codex", manager: .npm,
            packageIdentifier: "@openai/codex", currentVersion: "1.0.0", targetVersion: "1.2.0", managerDisplayName: "npm"
        )
        let runner = FakeProcessRunner(result: .success(FakeProcessRunner.output(status: 0)))
        let locator = FakeManagerLocator(paths: [.npm: URL(fileURLWithPath: "/opt/homebrew/bin/npm")])
        let probe = FakeVersionProbe(version: "1.0.0")
        let executor = AIUpdateExecutor(runner: runner, managerLocator: locator, versionProbe: probe)

        let results = await executor.execute(UpdateExecutionPlan(executable: [item], skipped: []))
        XCTAssertEqual(results.first?.outcome, .versionMismatch(observed: "1.0.0"))
    }

    func testExecutorReportsManagerUnavailableAndRunsNoProcess() async {
        let item = UpdateExecutionPlan.Item(
            key: key(path: "/bin/codex"), displayName: "Codex", manager: .npm,
            packageIdentifier: "@openai/codex", currentVersion: "1.0.0", targetVersion: "1.2.0", managerDisplayName: "npm"
        )
        let runner = FakeProcessRunner(result: .success(FakeProcessRunner.output(status: 0)))
        let locator = FakeManagerLocator(paths: [:])
        let probe = FakeVersionProbe(version: "1.2.0")
        let executor = AIUpdateExecutor(runner: runner, managerLocator: locator, versionProbe: probe)

        let results = await executor.execute(UpdateExecutionPlan(executable: [item], skipped: []))
        XCTAssertEqual(results.first?.outcome, .managerUnavailable)
        let runs = await runner.recordedRuns()
        XCTAssertTrue(runs.isEmpty)
    }

    func testExecutorReportsFailedTimedOutAndCancelled() async {
        let item = UpdateExecutionPlan.Item(
            key: key(path: "/bin/codex"), displayName: "Codex", manager: .npm,
            packageIdentifier: "@openai/codex", currentVersion: "1.0.0", targetVersion: "1.2.0", managerDisplayName: "npm"
        )
        let locator = FakeManagerLocator(paths: [.npm: URL(fileURLWithPath: "/opt/homebrew/bin/npm")])
        let probe = FakeVersionProbe(version: "1.2.0")

        let failRunner = FakeProcessRunner(result: .success(FakeProcessRunner.output(status: 1)))
        let failResults = await AIUpdateExecutor(runner: failRunner, managerLocator: locator, versionProbe: probe)
            .execute(UpdateExecutionPlan(executable: [item], skipped: []))
        XCTAssertEqual(failResults.first?.outcome, .failed(terminationStatus: 1))

        let timeoutRunner = FakeProcessRunner(result: .success(FakeProcessRunner.output(status: 0, didTimeout: true)))
        let timeoutResults = await AIUpdateExecutor(runner: timeoutRunner, managerLocator: locator, versionProbe: probe)
            .execute(UpdateExecutionPlan(executable: [item], skipped: []))
        XCTAssertEqual(timeoutResults.first?.outcome, .timedOut)

        let cancelRunner = FakeProcessRunner(result: .failure(CancellationError()))
        let cancelResults = await AIUpdateExecutor(runner: cancelRunner, managerLocator: locator, versionProbe: probe)
            .execute(UpdateExecutionPlan(executable: [item], skipped: []))
        XCTAssertEqual(cancelResults.first?.outcome, .cancelled)
    }

    // MARK: - LocalInstalledVersionProbe.parseVersion

    func testParseVersionHandlesNpmPnpmAndPipxLayouts() {
        XCTAssertEqual(
            LocalInstalledVersionProbe.parseVersion(from: "@openai/codex@1.2.3", packageIdentifier: "@openai/codex"),
            "1.2.3"
        )
        XCTAssertEqual(
            LocalInstalledVersionProbe.parseVersion(from: "  @aiden-cli/core@2.0.1  ", packageIdentifier: "@aiden-cli/core"),
            "2.0.1"
        )
        XCTAssertEqual(
            LocalInstalledVersionProbe.parseVersion(from: "aider-chat 3.1.0", packageIdentifier: "aider-chat"),
            "3.1.0"
        )
        XCTAssertNil(
            LocalInstalledVersionProbe.parseVersion(from: "some-other-pkg@1.0.0", packageIdentifier: "@openai/codex")
        )
    }

    func testListArgumentsAreFixedPerManager() {
        XCTAssertEqual(
            LocalInstalledVersionProbe.listArguments(manager: .npm, packageIdentifier: "@openai/codex"),
            ["ls", "--global", "--depth", "0", "@openai/codex"]
        )
        XCTAssertEqual(LocalInstalledVersionProbe.listArguments(manager: .pnpm, packageIdentifier: "x"), ["ls", "--global"])
        XCTAssertEqual(LocalInstalledVersionProbe.listArguments(manager: .pipx, packageIdentifier: "x"), ["list", "--short"])
    }

    // MARK: - Selection plan button responsiveness

    func testSelectionInitNeverDropsUnsupportedOnlyRows() {
        let unsupportedRow = AIUpdateSelectionPlan.SelectedRow(
            key: key(kind: .skill, path: "/s/skill"),
            displayName: "Local Skill"
        )
        let plan = AIUpdateSelectionPlan(selection: [unsupportedRow], assets: [], results: [:])
        XCTAssertTrue(plan.hasSelection)
        XCTAssertEqual(plan.unsupported.map(\.key), [unsupportedRow.key])
        XCTAssertTrue(plan.checkableKeys.isEmpty)
    }

    func testSelectionInitDeduplicatesRowsByStableKey() {
        let supported = asset(path: "/bin/codex", version: "1.0.0")
        let rowA = AIUpdateSelectionPlan.SelectedRow(key: supported.key, displayName: "Codex (alias A)")
        let rowB = AIUpdateSelectionPlan.SelectedRow(key: supported.key, displayName: "Codex (alias B)")
        let plan = AIUpdateSelectionPlan(selection: [rowA, rowB], assets: [supported], results: [:])
        XCTAssertEqual(plan.selected.count, 1)
        XCTAssertEqual(plan.selected.first?.displayName, supported.displayName)
    }
}

// MARK: - Fakes (no real process ever runs)

private actor FakeProcessRunner: CLIProcessRunning {
    struct Run: Sendable {
        let executableURL: URL
        let arguments: [String]
        let environment: [String: String]
    }

    private let result: Result<CLIProcessOutput, Error>
    private var runs: [Run] = []

    init(result: Result<CLIProcessOutput, Error>) {
        self.result = result
    }

    static func output(status: Int32, didTimeout: Bool = false) -> CLIProcessOutput {
        CLIProcessOutput(
            standardOutput: Data(),
            standardError: Data(),
            terminationStatus: status,
            didTimeout: didTimeout,
            outputTruncated: false
        )
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> CLIProcessOutput {
        runs.append(Run(executableURL: executableURL, arguments: arguments, environment: environment))
        switch result {
        case .success(let output): return output
        case .failure(let error): throw error
        }
    }

    func recordedRuns() -> [Run] { runs }
}

private struct FakeManagerLocator: UpdateManagerLocating {
    let paths: [UpdateExecutionManager: URL]
    func locate(_ manager: UpdateExecutionManager) -> URL? { paths[manager] }
}

private struct FakeVersionProbe: InstalledVersionProbing {
    let version: String?
    func installedVersion(manager: UpdateExecutionManager, packageIdentifier: String) async -> String? { version }
}
