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
        let runner = RecordingRunner(output: output(stdout: "", stderr: "claude v0.9.1\n"))
        let probe = SafeCLIVersionProbe(runner: runner, locator: AlwaysExecutableLocator())

        let result = try await probe.probeVersion(probeID: "claude", homeDirectory: home)

        XCTAssertEqual(result.version, "claude v0.9.1")
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
