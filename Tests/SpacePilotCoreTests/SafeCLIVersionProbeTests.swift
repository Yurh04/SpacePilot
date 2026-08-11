import XCTest
@testable import SpacePilotCore

final class SafeCLIVersionProbeTests: XCTestCase {

    // MARK: - Controllable runner

    /// Records how it was invoked and returns a scripted output, so tests can
    /// assert the probe never uses a shell or `/usr/bin/env` and always passes a
    /// fixed environment.
    private final class RecordingRunner: CLIProcessRunning, @unchecked Sendable {
        struct Invocation {
            let executableURL: URL
            let arguments: [String]
            let environment: [String: String]
        }

        private let lock = NSLock()
        private var _invocations: [Invocation] = []
        var invocations: [Invocation] {
            lock.lock(); defer { lock.unlock() }
            return _invocations
        }
        let output: CLIProcessOutput
        let error: (any Error)?

        init(output: CLIProcessOutput, error: (any Error)? = nil) {
            self.output = output
            self.error = error
        }

        private func record(_ invocation: Invocation) {
            lock.lock(); defer { lock.unlock() }
            _invocations.append(invocation)
        }

        func run(
            executableURL: URL,
            arguments: [String],
            environment: [String: String],
            timeout: Duration,
            maximumOutputBytes: Int
        ) async throws -> CLIProcessOutput {
            record(Invocation(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment
            ))
            if let error { throw error }
            return output
        }
    }

    private struct AlwaysExecutableLocator: ExecutableLocating {
        func isExecutableFile(at url: URL) -> Bool { true }
    }

    private struct NeverExecutableLocator: ExecutableLocating {
        func isExecutableFile(at url: URL) -> Bool { false }
    }

    private func output(
        stdout: String = "",
        stderr: String = "",
        status: Int32 = 0,
        didTimeout: Bool = false,
        truncated: Bool = false
    ) -> CLIProcessOutput {
        CLIProcessOutput(
            standardOutput: Data(stdout.utf8),
            standardError: Data(stderr.utf8),
            terminationStatus: status,
            didTimeout: didTimeout,
            outputTruncated: truncated
        )
    }

    private let home = URL(filePath: "/Users/test")

    private func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// Creates the `node_modules/<packageID>` directory that the FNM/NVM
    /// candidate gate now requires so a version root counts as having actually
    /// installed the fixed npm package. `versionRootRelativePath` points at the
    /// version directory (for example `.local/share/fnm/node-versions/v24.18.0`).
    private func makeInstalledNodePackage(
        home: URL,
        versionRootRelativePath: String,
        nodeModulesTail: String = "installation/lib/node_modules",
        packageIdentifier: String
    ) throws {
        var packageURL = home
            .appending(path: versionRootRelativePath, directoryHint: .isDirectory)
            .appending(path: nodeModulesTail, directoryHint: .isDirectory)
        for component in packageIdentifier.split(separator: "/", omittingEmptySubsequences: true) {
            packageURL = packageURL.appending(path: String(component), directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
    }

    // MARK: - Whitelist / unknown ID

    func testKnownProbeRunsFixedExecutableAndArgumentsWithFixedEnvironment() async throws {
        let runner = RecordingRunner(output: output(stdout: "codex 1.2.3\n"))
        let probe = SafeCLIVersionProbe(
            runner: runner,
            locator: AlwaysExecutableLocator()
        )

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertEqual(result.version, "codex 1.2.3")
        XCTAssertNil(result.coverageFailure)
        let invocation = try XCTUnwrap(runner.invocations.first)
        // Absolute, whitelist-defined path — never a shell or env.
        XCTAssertTrue(invocation.executableURL.path.hasPrefix("/"))
        XCTAssertNotEqual(invocation.executableURL.lastPathComponent, "sh")
        XCTAssertNotEqual(invocation.executableURL.lastPathComponent, "bash")
        XCTAssertNotEqual(invocation.executableURL.lastPathComponent, "env")
        XCTAssertEqual(invocation.arguments, ["--version"])
        XCTAssertEqual(invocation.environment, SafeCLIVersionProbe.fixedEnvironment)
        XCTAssertFalse(invocation.environment.keys.contains("HOME"))
    }

    func testAidenProbeUsesOnlyFixedBasenameCandidatesAndVersionArgs() async throws {
        let runner = RecordingRunner(output: output(stdout: "aiden 1.8.44\n"))
        let probe = SafeCLIVersionProbe(
            runner: runner,
            locator: AlwaysExecutableLocator()
        )

        let result = try await probe.probeVersion(probeID: "aiden", homeDirectory: home)

        XCTAssertEqual(result.version, "aiden 1.8.44")
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.executableURL.lastPathComponent, "aiden")
        XCTAssertEqual(invocation.arguments, ["--version"])
        XCTAssertEqual(invocation.environment, SafeCLIVersionProbe.fixedEnvironment)
    }

    func testProbeFindsFNMInstallationBinWithVerifiedScopedEnvironment() async throws {
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/codex",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: executable)
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v24.18.0",
            packageIdentifier: "@openai/codex"
        )
        let runner = RecordingRunner(output: output(stdout: "codex 0.42.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable.standardizedFileURL.resolvingSymlinksInPath())
        let invocation = try XCTUnwrap(runner.invocations.first)
        XCTAssertEqual(invocation.arguments, ["--version"])
        XCTAssertTrue(invocation.environment["PATH"]?.hasPrefix(executable.deletingLastPathComponent().path + ":") == true)
        XCTAssertFalse(invocation.environment.keys.contains("HOME"))
        XCTAssertFalse(invocation.environment["PATH"]?.contains("fnm_multishells") == true)
    }

    func testProbeFindsLibraryPnpmBinForAiden() async throws {
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(path: "Library/pnpm/bin/aiden", directoryHint: .notDirectory)
        try makeExecutable(at: executable)
        let runner = RecordingRunner(output: output(stdout: "aiden 1.8.44\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "aiden", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable)
        XCTAssertEqual(runner.invocations.first?.environment, SafeCLIVersionProbe.fixedEnvironment)
    }

    func testProbeFindsMerlinExactHomeRelativeBin() async throws {
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(path: ".merlin-cli/bin/merlin-cli", directoryHint: .notDirectory)
        try makeExecutable(at: executable)
        let runner = RecordingRunner(output: output(stdout: "merlin-cli 3.2.1\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "merlin-cli", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable)
        XCTAssertEqual(result.version, "merlin-cli 3.2.1")
        XCTAssertEqual(runner.invocations.first?.environment, SafeCLIVersionProbe.fixedEnvironment)
    }

    func testProbeFindsTraexCurrentSymlinkExecutable() async throws {
        let tree = try TemporaryTree(files: [:])
        // ~/.local/share/traex/current -> releases/<version>/, then /traex.
        let release = tree.url.appending(
            path: ".local/share/traex/releases/0.200.19/traex",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: release)
        let currentLink = tree.url.appending(path: ".local/share/traex/current", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(
            at: currentLink,
            withDestinationURL: tree.url.appending(path: ".local/share/traex/releases/0.200.19", directoryHint: .isDirectory)
        )
        let runner = RecordingRunner(output: output(stdout: "traex 0.200.19\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "traex", homeDirectory: tree.url)

        // The home-relative candidate is used as-is (the `current` symlink is
        // resolved by the filesystem when executed); the executable is found and
        // its version parsed.
        let expected = tree.url.appending(path: ".local/share/traex/current/traex", directoryHint: .notDirectory)
        XCTAssertEqual(result.executableURL, expected)
        XCTAssertEqual(result.version, "traex 0.200.19")
    }

    func testProbeFindsUvToolBinForMira() async throws {
        let tree = try TemporaryTree(files: [:])
        // Fixed uv tool template: ~/.local/share/uv/tools/togo-cli/bin/mira.
        let executable = tree.url.appending(
            path: ".local/share/uv/tools/togo-cli/bin/mira",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: executable)
        let runner = RecordingRunner(output: output(stdout: "mira 1.4.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "mira", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(result.version, "mira 1.4.0")
        XCTAssertEqual(runner.invocations.first?.environment, SafeCLIVersionProbe.fixedEnvironment)
    }

    func testUvToolSymlinkEscapeIsRejected() async throws {
        let tree = try TemporaryTree(files: [:])
        // The tool root is a symlink pointing outside the uv tools tree; the
        // resolved executable escapes its declared root and must be rejected.
        let outside = tree.url.appending(path: "outside/togo-cli", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: outside.appending(path: "bin", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        try makeExecutable(at: outside.appending(path: "bin/aime", directoryHint: .notDirectory))
        let uvTools = tree.url.appending(path: ".local/share/uv/tools", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: uvTools, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: uvTools.appending(path: "togo-cli", directoryHint: .isDirectory),
            withDestinationURL: outside
        )
        let runner = RecordingRunner(output: output(stdout: "aime 1.0.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "aime", homeDirectory: tree.url)

        // No home-relative or uv candidate is valid, so the CLI is unavailable
        // and no process is run.
        XCTAssertNil(result.executableURL)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testProbeFindsLarkCliHomebrewBin() async throws {
        let runner = RecordingRunner(output: output(stdout: "lark-cli 2.5.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "lark-cli", homeDirectory: home)

        _ = result
        let invocation = try XCTUnwrap(runner.invocations.first)
        // Homebrew path is preferred first for lark-cli.
        XCTAssertEqual(invocation.executableURL.path, "/opt/homebrew/bin/lark-cli")
        XCTAssertEqual(invocation.environment, SafeCLIVersionProbe.fixedEnvironment)
    }

    func testVersionFailureStillReturnsExecutableAndCoverageFailure() async throws {
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/claude",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: executable)
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v24.18.0",
            packageIdentifier: "@anthropic-ai/claude-code"
        )
        let runner = RecordingRunner(output: output(stdout: "not a version\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "claude", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(result.coverageFailure, .invalidOutput)
        XCTAssertNil(result.version)
    }

    func testNonExecutableManagedCandidateDoesNotCountAsInstalled() async throws {
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/claude",
            directoryHint: .notDirectory
        )
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v24.18.0",
            packageIdentifier: "@anthropic-ai/claude-code"
        )
        let runner = RecordingRunner(output: output(stdout: "claude 1.0.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "claude", homeDirectory: tree.url)

        XCTAssertNil(result.executableURL)
        XCTAssertEqual(result.coverageFailure, .unavailable)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testFNMVersionSelectionIsDeterministicAndPrefersHighestParsedVersion() async throws {
        let tree = try TemporaryTree(files: [:])
        let old = tree.url.appending(path: ".local/share/fnm/node-versions/v18.0.0/installation/bin/codex", directoryHint: .notDirectory)
        let newest = tree.url.appending(path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/codex", directoryHint: .notDirectory)
        try makeExecutable(at: old)
        try makeExecutable(at: newest)
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v18.0.0",
            packageIdentifier: "@openai/codex"
        )
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v24.18.0",
            packageIdentifier: "@openai/codex"
        )
        let runner = RecordingRunner(output: output(stdout: "codex 1.0.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, newest.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testNodePackageToolRejectsUnverifiedGenericBasenameCandidates() async throws {
        // `one` is distributed as the npm package @dp/one-cli. The generic
        // basename candidates (/usr/local/bin/one, /opt/homebrew/bin/one,
        // ~/.local/bin/one, ~/Library/pnpm/bin/one) carry no package identity and
        // must NOT be offered for a node-package tool. AlwaysExecutableLocator
        // claims every path is executable, so if any generic candidate were
        // still offered it would run; instead only the package-ID gated
        // FNM/NVM templates apply, none exist here, so nothing runs.
        let runner = RecordingRunner(output: output(stdout: "one 9.9.9\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "one", homeDirectory: home)

        XCTAssertNil(result.executableURL)
        XCTAssertEqual(result.coverageFailure, .unavailable)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testFNMSymlinkEscapeIsRejectedButInternalSymlinkIsAllowed() async throws {
        let tree = try TemporaryTree(files: [:])
        let root = tree.url.appending(path: ".local/share/fnm/node-versions", directoryHint: .isDirectory)
        let outside = tree.url.appending(path: "outside/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let escape = root.appending(path: "v99.0.0", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: outside)

        let realBin = root.appending(path: "v24.18.0/installation/real-bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: realBin, withIntermediateDirectories: true)
        let internalBin = root.appending(path: "v24.18.0/installation/bin", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: internalBin, withDestinationURL: realBin)
        let executable = realBin.appending(path: "codex", directoryHint: .notDirectory)
        try makeExecutable(at: executable)
        try makeInstalledNodePackage(
            home: tree.url,
            versionRootRelativePath: ".local/share/fnm/node-versions/v24.18.0",
            packageIdentifier: "@openai/codex"
        )
        let runner = RecordingRunner(output: output(stdout: "codex 1.0.0\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: tree.url)

        XCTAssertEqual(result.executableURL, executable.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertNotEqual(result.executableURL?.path, outside.appending(path: "installation/bin/codex").path)
    }

    func testFNMBasenameWithoutInstalledPackageIDIsNotExecuted() async throws {
        // A Node version directory contains an executable that merely shares the
        // basename `one`, but the fixed npm package `@dp/one-cli` was never
        // installed under node_modules. The candidate must be rejected: no
        // record, no process run — the probe never attributes an unrelated
        // binary to the AI tool. (`one` has no absolute/app-bundled fallback, so
        // the FNM candidate is the only source and rejection means unavailable.)
        let tree = try TemporaryTree(files: [:])
        let executable = tree.url.appending(
            path: ".local/share/fnm/node-versions/v24.18.0/installation/bin/one",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: executable)
        // Intentionally do NOT create installation/lib/node_modules/@dp/one-cli.
        let runner = RecordingRunner(output: output(stdout: "one 9.9.9\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "one", homeDirectory: tree.url)

        XCTAssertNil(result.executableURL)
        XCTAssertEqual(result.coverageFailure, .unavailable)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    func testTraexResolvesKnownAliasesAsCanonicalDedupedEvidence() async throws {
        // The real machine layout: ~/.local/bin/{trae-cli,trae-agent} are
        // symlinks that ultimately resolve to the same traex executable. The
        // probe must surface both aliases as evidence (as declared, so the UI
        // shows the names the user knows) deduped by path and sorted.
        let tree = try TemporaryTree(files: [:])
        let primary = tree.url.appending(
            path: ".local/share/traex/current/traex",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: primary)
        let localBin = tree.url.appending(path: ".local/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        for alias in ["trae-cli", "trae-agent"] {
            try FileManager.default.createSymbolicLink(
                at: localBin.appending(path: alias, directoryHint: .notDirectory),
                withDestinationURL: primary
            )
        }
        let runner = RecordingRunner(output: output(stdout: "traex 0.200.19\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "traex", homeDirectory: tree.url)

        let aliasNames = result.aliasExecutableURLs.map(\.lastPathComponent)
        XCTAssertEqual(aliasNames, ["trae-agent", "trae-cli"])
        // The aliases are declared as their ~/.local/bin paths, not the resolved
        // traex target, so the UI can present the familiar names.
        for url in result.aliasExecutableURLs {
            XCTAssertTrue(url.path.hasSuffix(".local/bin/\(url.lastPathComponent)"))
        }
    }

    func testTraexAliasEvidenceExcludesAliasesResolvingElsewhere() async throws {
        // A ~/.local/bin/trae-cli that points at an unrelated executable must
        // not be surfaced as evidence for the traex primary.
        let tree = try TemporaryTree(files: [:])
        let primary = tree.url.appending(
            path: ".local/share/traex/current/traex",
            directoryHint: .notDirectory
        )
        try makeExecutable(at: primary)
        let unrelated = tree.url.appending(path: "other/trae-cli", directoryHint: .notDirectory)
        try makeExecutable(at: unrelated)
        let localBin = tree.url.appending(path: ".local/bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: localBin.appending(path: "trae-cli", directoryHint: .notDirectory),
            withDestinationURL: unrelated
        )
        try FileManager.default.createSymbolicLink(
            at: localBin.appending(path: "trae-agent", directoryHint: .notDirectory),
            withDestinationURL: primary
        )
        let runner = RecordingRunner(output: output(stdout: "traex 0.200.19\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: LocalExecutableLocator())

        let result = try await probe.probeVersion(probeID: "traex", homeDirectory: tree.url)

        XCTAssertEqual(result.aliasExecutableURLs.map(\.lastPathComponent), ["trae-agent"])
    }

    func testUnknownProbeIDIsRejectedWithoutRunningProcess() async {
        let runner = RecordingRunner(output: output())
        let probe = SafeCLIVersionProbe(
            runner: runner,
            locator: AlwaysExecutableLocator()
        )

        do {
            _ = try await probe.probeVersion(probeID: "totally-unknown", homeDirectory: home)
            XCTFail("Expected UnknownProbeError")
        } catch let error as SafeCLIVersionProbe.UnknownProbeError {
            XCTAssertEqual(error.probeID, "totally-unknown")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertTrue(runner.invocations.isEmpty, "No process should be started for unknown IDs")
    }

    func testMissingExecutableReturnsUnavailableWithoutRunning() async throws {
        let runner = RecordingRunner(output: output())
        let probe = SafeCLIVersionProbe(
            runner: runner,
            locator: NeverExecutableLocator()
        )

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertNil(result.executableURL)
        XCTAssertEqual(result.coverageFailure, .unavailable)
        XCTAssertTrue(runner.invocations.isEmpty)
    }

    // MARK: - Timeout / exit code / output shape

    func testTimeoutMapsToTimeoutCoverageFailure() async throws {
        let runner = RecordingRunner(output: output(didTimeout: true))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertEqual(result.coverageFailure, .timeout)
        XCTAssertNil(result.version)
    }

    func testNonZeroExitMapsToInvalidOutput() async throws {
        let runner = RecordingRunner(output: output(stdout: "1.0.0\n", status: 1))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertEqual(result.coverageFailure, .invalidOutput)
    }

    func testEmptyOutputMapsToInvalidOutput() async throws {
        let runner = RecordingRunner(output: output(stdout: "", stderr: ""))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertNil(result.version)
        XCTAssertEqual(result.coverageFailure, .invalidOutput)
    }

    func testMalformedBannerWithoutDigitsIsRejected() async throws {
        let runner = RecordingRunner(output: output(stdout: "hello world\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertNil(result.version)
        XCTAssertEqual(result.coverageFailure, .invalidOutput)
    }

    func testVersionParsedFromStderrFallback() async throws {
        let runner = RecordingRunner(output: output(stdout: "", stderr: "codex v0.9.1\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertEqual(result.version, "codex v0.9.1")
        XCTAssertNil(result.coverageFailure)
    }

    func testTruncatedOutputSurfacesOutputTruncatedFailure() async throws {
        let runner = RecordingRunner(output: output(stdout: "1.0.0\n", truncated: true))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "codex", homeDirectory: home)

        XCTAssertEqual(result.version, "1.0.0")
        XCTAssertEqual(result.coverageFailure, .outputTruncated)
    }

    // MARK: - parseVersion unit checks

    func testParseVersionRequiresDigitAndBoundsLength() {
        XCTAssertEqual(SafeCLIVersionProbe.parseVersion(from: Data("v1.2.3".utf8)), "v1.2.3")
        XCTAssertNil(SafeCLIVersionProbe.parseVersion(from: Data("no digits here".utf8)))
        XCTAssertNil(SafeCLIVersionProbe.parseVersion(from: Data("".utf8)))
        // A very long line (over 200 chars) is skipped, not returned.
        let longLine = String(repeating: "9", count: 5000)
        XCTAssertNil(SafeCLIVersionProbe.parseVersion(from: Data(longLine.utf8)))
    }

    // MARK: - Cancellation

    func testCancellationDuringRunPropagates() async throws {
        struct CancellingRunner: CLIProcessRunning {
            func run(
                executableURL: URL,
                arguments: [String],
                environment: [String: String],
                timeout: Duration,
                maximumOutputBytes: Int
            ) async throws -> CLIProcessOutput {
                throw CancellationError()
            }
        }
        let probe = SafeCLIVersionProbe(
            runner: CancellingRunner(),
            locator: AlwaysExecutableLocator()
        )

        do {
            _ = try await probe.probeVersion(probeID: "codex", homeDirectory: home)
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // Expected.
        }
    }

    // MARK: - Real runner: dual-stream drain must not deadlock

    func testDefaultRunnerDrainsLargeDualStreamsWithoutDeadlock() async throws {
        // Emit large volumes to BOTH stdout and stderr. Serial draining would
        // deadlock; concurrent draining must complete and cap each stream.
        let script = """
        import sys
        big = "A" * (2 * 1024 * 1024)
        sys.stdout.write(big)
        sys.stderr.write(big)
        sys.stdout.flush()
        sys.stderr.flush()
        """
        guard let python = Self.locatePython() else {
            throw XCTSkip("No python3 available to drive the dual-stream test")
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "spacepilot-dualstream-\(UUID().uuidString).py")
        try Data(script.utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let runner = DefaultCLIProcessRunner()
        let cap = 64 * 1024
        let result = try await runner.run(
            executableURL: python,
            arguments: [scriptURL.path],
            environment: SafeCLIVersionProbe.fixedEnvironment,
            timeout: .seconds(10),
            maximumOutputBytes: cap
        )

        XCTAssertLessThanOrEqual(result.standardOutput.count, cap)
        XCTAssertLessThanOrEqual(result.standardError.count, cap)
        XCTAssertTrue(result.outputTruncated)
        XCTAssertEqual(result.terminationStatus, 0)
        XCTAssertFalse(result.didTimeout)
    }

    private static func locatePython() -> URL? {
        for path in ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"] {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(filePath: path)
            }
        }
        return nil
    }

    // MARK: - Real runner: hard timeout must kill a SIGTERM-ignoring child

    func testDefaultRunnerHardTimeoutKillsSigtermIgnoringChild() async throws {
        // A child that ignores SIGTERM and loops forever. Without SIGKILL
        // escalation the "hard" timeout would hang indefinitely.
        let script = """
        import signal, time, sys
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        sys.stderr.write("ready\\n")
        sys.stderr.flush()
        while True:
            time.sleep(0.2)
        """
        guard let python = Self.locatePython() else {
            throw XCTSkip("No python3 available for the timeout-escalation test")
        }
        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "spacepilot-ignoreterm-\(UUID().uuidString).py")
        try Data(script.utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let runner = DefaultCLIProcessRunner(killGracePeriod: .seconds(1))
        let start = ContinuousClock.now
        let result = try await runner.run(
            executableURL: python,
            arguments: [scriptURL.path],
            environment: SafeCLIVersionProbe.fixedEnvironment,
            timeout: .seconds(1),
            maximumOutputBytes: 64 * 1024
        )
        let elapsed = ContinuousClock.now - start

        XCTAssertTrue(result.didTimeout)
        // Bounded by timeout (1s) + grace (1s) plus scheduling slack.
        XCTAssertLessThan(elapsed, .seconds(8))
    }

    func testDefaultRunnerCancellationOfSigtermIgnoringChildIsBounded() async throws {
        let script = """
        import signal, time, sys
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        sys.stderr.write("ready\\n")
        sys.stderr.flush()
        while True:
            time.sleep(0.2)
        """
        guard let python = Self.locatePython() else {
            throw XCTSkip("No python3 available for the cancellation-escalation test")
        }
        let scriptURL = FileManager.default.temporaryDirectory
            .appending(path: "spacepilot-cancelterm-\(UUID().uuidString).py")
        try Data(script.utf8).write(to: scriptURL)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let runner = DefaultCLIProcessRunner(killGracePeriod: .seconds(1))
        let task = Task {
            try await runner.run(
                executableURL: python,
                arguments: [scriptURL.path],
                environment: SafeCLIVersionProbe.fixedEnvironment,
                timeout: .seconds(30),
                maximumOutputBytes: 64 * 1024
            )
        }
        // Give the child time to start and ignore SIGTERM, then cancel.
        try? await Task.sleep(for: .milliseconds(300))
        let start = ContinuousClock.now
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            let elapsed = ContinuousClock.now - start
            // SIGTERM ignored, so SIGKILL after grace must still bound this.
            XCTAssertLessThan(elapsed, .seconds(8))
        }
    }
}
