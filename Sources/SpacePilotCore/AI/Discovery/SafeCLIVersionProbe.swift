import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The outcome of running a CLI process under strict limits.
public struct CLIProcessOutput: Sendable {
    public let standardOutput: Data
    public let standardError: Data
    public let terminationStatus: Int32
    public let didTimeout: Bool
    public let outputTruncated: Bool

    public init(
        standardOutput: Data,
        standardError: Data,
        terminationStatus: Int32,
        didTimeout: Bool,
        outputTruncated: Bool
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.terminationStatus = terminationStatus
        self.didTimeout = didTimeout
        self.outputTruncated = outputTruncated
    }
}

/// Runs a single executable with bounded time and output. Injected so tests can
/// exercise the probe deterministically without spawning real processes.
public protocol CLIProcessRunning: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> CLIProcessOutput
}

/// Reports whether a candidate path is an executable file. Injected for
/// deterministic tests.
public protocol ExecutableLocating: Sendable {
    func isExecutableFile(at url: URL) -> Bool
}

public struct LocalExecutableLocator: ExecutableLocating {
    public init() {}

    public func isExecutableFile(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let path = url.path
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}

/// The result of probing a tool's CLI version.
public struct SafeCLIProbeResult: Sendable, Equatable {
    public let executableURL: URL?
    public let version: String?
    public let coverageFailure: AIToolCoverageFailure?

    public init(
        executableURL: URL?,
        version: String?,
        coverageFailure: AIToolCoverageFailure?
    ) {
        self.executableURL = executableURL
        self.version = version
        self.coverageFailure = coverageFailure
    }
}

/// Reads a CLI tool's version safely.
///
/// Guarantees:
/// - Only whitelisted probe IDs run; an unknown ID is rejected *before* any
///   process is created.
/// - The executable is always an absolute, whitelist-defined candidate path.
///   Nothing from a manifest, config file, or `PATH` is ever executed, and the
///   probe never invokes a shell or `/usr/bin/env`.
/// - The child runs with a fixed minimal environment, a hard timeout, a byte
///   cap on captured output, and cooperative cancellation.
public struct SafeCLIVersionProbe: Sendable {
    /// A whitelisted probe: fixed candidate executable locations and fixed
    /// version arguments. No field here is ever sourced from external data.
    struct ProbeSpec: Sendable {
        /// Fixed executable basename. Manager templates append this basename;
        /// they never read package manifests or shell PATH.
        let basename: String
        /// Absolute candidate paths, tried in order.
        let absoluteCandidatePaths: [String]
        /// Home-relative candidate paths, resolved against the home directory.
        let homeRelativeCandidatePaths: [String]
        /// Fixed app-bundled executable paths, never discovered by display name
        /// or filesystem search.
        let appBundledAbsoluteCandidatePaths: [String]
        /// Fixed arguments used to request the version (for example `--version`).
        let versionArguments: [String]

        init(
            basename: String,
            absoluteCandidatePaths: [String],
            homeRelativeCandidatePaths: [String],
            appBundledAbsoluteCandidatePaths: [String] = [],
            versionArguments: [String]
        ) {
            self.basename = basename
            self.absoluteCandidatePaths = absoluteCandidatePaths
            self.homeRelativeCandidatePaths = homeRelativeCandidatePaths
            self.appBundledAbsoluteCandidatePaths = appBundledAbsoluteCandidatePaths
            self.versionArguments = versionArguments
        }
    }

    private struct ProbeCandidate: Sendable {
        let executableURL: URL
        let environment: [String: String]
    }

    /// The only environment the child ever sees. Deliberately minimal, but the
    /// PATH covers the standard Homebrew and system locations so tools installed
    /// via `/usr/bin/env node` shebangs can still resolve their interpreter.
    /// This list is a fixed code constant; it never inherits the host
    /// environment or accepts any external input.
    static let fixedEnvironment: [String: String] = [
        "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    ]

    /// The whitelist. Keys must match `AIToolDefinition.cliProbeID`.
    static let whitelist: [String: ProbeSpec] = [
        "codex": ProbeSpec(
            basename: "codex",
            absoluteCandidatePaths: ["/usr/local/bin/codex", "/opt/homebrew/bin/codex"],
            homeRelativeCandidatePaths: [".local/bin/codex"],
            appBundledAbsoluteCandidatePaths: ["/Applications/ChatGPT.app/Contents/Resources/codex"],
            versionArguments: ["--version"]
        ),
        "claude": ProbeSpec(
            basename: "claude",
            absoluteCandidatePaths: ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"],
            homeRelativeCandidatePaths: [".local/bin/claude"],
            versionArguments: ["--version"]
        ),
        "cursor": ProbeSpec(
            basename: "cursor",
            absoluteCandidatePaths: ["/usr/local/bin/cursor", "/opt/homebrew/bin/cursor"],
            homeRelativeCandidatePaths: [],
            versionArguments: ["--version"]
        ),
        "windsurf": ProbeSpec(
            basename: "windsurf",
            absoluteCandidatePaths: ["/usr/local/bin/windsurf", "/opt/homebrew/bin/windsurf"],
            homeRelativeCandidatePaths: [],
            versionArguments: ["--version"]
        ),
        "gemini": ProbeSpec(
            basename: "gemini",
            absoluteCandidatePaths: ["/usr/local/bin/gemini", "/opt/homebrew/bin/gemini"],
            homeRelativeCandidatePaths: [".local/bin/gemini"],
            versionArguments: ["--version"]
        ),
        "opencode": ProbeSpec(
            basename: "opencode",
            absoluteCandidatePaths: ["/usr/local/bin/opencode", "/opt/homebrew/bin/opencode"],
            homeRelativeCandidatePaths: [".local/bin/opencode"],
            versionArguments: ["--version"]
        ),
        "aider": ProbeSpec(
            basename: "aider",
            absoluteCandidatePaths: ["/usr/local/bin/aider", "/opt/homebrew/bin/aider"],
            homeRelativeCandidatePaths: [".local/bin/aider"],
            versionArguments: ["--version"]
        ),
        "aiden": ProbeSpec(
            basename: "aiden",
            absoluteCandidatePaths: ["/usr/local/bin/aiden", "/opt/homebrew/bin/aiden"],
            homeRelativeCandidatePaths: [".local/bin/aiden"],
            versionArguments: ["--version"]
        ),
        "trae": ProbeSpec(
            basename: "trae",
            absoluteCandidatePaths: ["/usr/local/bin/trae", "/opt/homebrew/bin/trae"],
            homeRelativeCandidatePaths: [".local/bin/trae"],
            versionArguments: ["--version"]
        ),
        "traework": ProbeSpec(
            basename: "traework",
            absoluteCandidatePaths: ["/usr/local/bin/traework", "/opt/homebrew/bin/traework"],
            homeRelativeCandidatePaths: [".local/bin/traework"],
            versionArguments: ["--version"]
        ),
        "antigravity": ProbeSpec(
            basename: "antigravity",
            absoluteCandidatePaths: ["/usr/local/bin/antigravity", "/opt/homebrew/bin/antigravity"],
            homeRelativeCandidatePaths: [".local/bin/antigravity"],
            versionArguments: ["--version"]
        ),
        "copilot": ProbeSpec(
            basename: "copilot",
            absoluteCandidatePaths: ["/usr/local/bin/copilot", "/opt/homebrew/bin/copilot"],
            homeRelativeCandidatePaths: [],
            versionArguments: ["--version"]
        ),
        "ollama": ProbeSpec(
            basename: "ollama",
            absoluteCandidatePaths: ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama"],
            homeRelativeCandidatePaths: [],
            versionArguments: ["--version"]
        )
    ]

    /// An unknown probe identifier was requested; nothing was executed.
    public struct UnknownProbeError: Error, Equatable {
        public let probeID: String
    }

    private let runner: any CLIProcessRunning
    private let locator: any ExecutableLocating
    private let timeout: Duration
    private let maximumOutputBytes: Int

    public init(
        runner: any CLIProcessRunning = DefaultCLIProcessRunner(),
        locator: any ExecutableLocating = LocalExecutableLocator(),
        timeout: Duration = .seconds(3),
        maximumOutputBytes: Int = 64 * 1024
    ) {
        self.runner = runner
        self.locator = locator
        self.timeout = timeout
        // Clamp to a sane positive per-stream cap so a zero/negative value can
        // never disable the bound.
        self.maximumOutputBytes = max(1, maximumOutputBytes)
    }

    /// Returns whether an identifier is a known, runnable probe.
    public static func isKnownProbe(_ probeID: String) -> Bool {
        whitelist[probeID] != nil
    }

    /// Probes the version for `probeID`. Throws `UnknownProbeError` for
    /// unrecognized identifiers without ever spawning a process. Propagates
    /// `CancellationError` on cooperative cancellation.
    public func probeVersion(
        probeID: String,
        homeDirectory: URL
    ) async throws -> SafeCLIProbeResult {
        guard let spec = Self.whitelist[probeID] else {
            throw UnknownProbeError(probeID: probeID)
        }

        let candidates = probeCandidates(for: spec, homeDirectory: homeDirectory)
        guard let candidate = candidates.first(where: { locator.isExecutableFile(at: $0.executableURL) }) else {
            return SafeCLIProbeResult(
                executableURL: nil,
                version: nil,
                coverageFailure: .unavailable
            )
        }

        try Task.checkCancellation()

        let output: CLIProcessOutput
        do {
            output = try await runner.run(
                executableURL: candidate.executableURL,
                arguments: spec.versionArguments,
                environment: candidate.environment,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return SafeCLIProbeResult(
                executableURL: candidate.executableURL,
                version: nil,
                coverageFailure: .unavailable
            )
        }

        // The runner terminates the child on cancellation but may still return a
        // completed output; make cancellation authoritative here.
        try Task.checkCancellation()

        if output.didTimeout {
            return SafeCLIProbeResult(
                executableURL: candidate.executableURL,
                version: nil,
                coverageFailure: .timeout
            )
        }

        let parsed = Self.parseVersion(from: output.standardOutput)
            ?? Self.parseVersion(from: output.standardError)

        if output.terminationStatus != 0 || parsed == nil {
            return SafeCLIProbeResult(
                executableURL: candidate.executableURL,
                version: parsed,
                coverageFailure: .invalidOutput
            )
        }

        return SafeCLIProbeResult(
            executableURL: candidate.executableURL,
            version: parsed,
            coverageFailure: output.outputTruncated ? .outputTruncated : nil
        )
    }

    private func probeCandidates(for spec: ProbeSpec, homeDirectory: URL) -> [ProbeCandidate] {
        var candidates: [ProbeCandidate] = []
        candidates.append(contentsOf: spec.absoluteCandidatePaths.map {
            ProbeCandidate(executableURL: URL(filePath: $0), environment: Self.fixedEnvironment)
        })
        candidates.append(contentsOf: spec.homeRelativeCandidatePaths.map {
            ProbeCandidate(
                executableURL: homeDirectory.appending(path: $0, directoryHint: .notDirectory),
                environment: Self.fixedEnvironment
            )
        })
        candidates.append(ProbeCandidate(
            executableURL: homeDirectory.appending(path: "Library/pnpm/bin/\(spec.basename)", directoryHint: .notDirectory),
            environment: Self.fixedEnvironment
        ))
        candidates.append(contentsOf: versionedManagerCandidates(
            homeDirectory: homeDirectory,
            managerRootRelativePath: ".local/share/fnm/node-versions",
            executableTail: "installation/bin/\(spec.basename)"
        ))
        candidates.append(contentsOf: versionedManagerCandidates(
            homeDirectory: homeDirectory,
            managerRootRelativePath: ".nvm/versions/node",
            executableTail: "bin/\(spec.basename)"
        ))
        candidates.append(contentsOf: spec.appBundledAbsoluteCandidatePaths.map {
            ProbeCandidate(executableURL: URL(filePath: $0), environment: Self.fixedEnvironment)
        })

        var seen = Set<String>()
        return candidates.filter { candidate in
            seen.insert(candidate.executableURL.standardizedFileURL.path).inserted
        }
    }

    private func versionedManagerCandidates(
        homeDirectory: URL,
        managerRootRelativePath: String,
        executableTail: String
    ) -> [ProbeCandidate] {
        let managerRoot = homeDirectory.appending(path: managerRootRelativePath, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard let versions = try? FileManager.default.contentsOfDirectory(
            at: managerRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return versions.compactMap { versionDirectory -> (candidate: ProbeCandidate, versionName: String)? in
            let canonicalVersionDirectory = versionDirectory.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalVersionDirectory.hasPathComponentPrefix(managerRoot),
                  (try? canonicalVersionDirectory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let executableURL = canonicalVersionDirectory.appending(path: executableTail, directoryHint: .notDirectory)
            let canonicalExecutable = executableURL.standardizedFileURL.resolvingSymlinksInPath()
            let installBin = canonicalExecutable.deletingLastPathComponent()
            guard canonicalExecutable.hasPathComponentPrefix(canonicalVersionDirectory),
                  installBin.hasPathComponentPrefix(canonicalVersionDirectory) else {
                return nil
            }
            return (ProbeCandidate(
                executableURL: canonicalExecutable,
                environment: Self.environment(prependingVerifiedBin: installBin)
            ), canonicalVersionDirectory.lastPathComponent)
        }
        .sorted { lhs, rhs in
            let lhsKey = VersionSortKey(lhs.versionName)
            let rhsKey = VersionSortKey(rhs.versionName)
            if lhsKey != rhsKey { return lhsKey > rhsKey }
            return lhs.candidate.executableURL.path < rhs.candidate.executableURL.path
        }
        .map(\.candidate)
    }

    private static func environment(prependingVerifiedBin bin: URL) -> [String: String] {
        var environment = fixedEnvironment
        environment["PATH"] = bin.path + ":" + (fixedEnvironment["PATH"] ?? "")
        return environment
    }

    /// Extracts a plausible version string from captured output. To reject
    /// malformed floods and arbitrary banners (for example `hello world`), the
    /// candidate must be a short, printable line that contains at least one
    /// digit. Anything else yields `nil`, which the caller treats as
    /// `invalidOutput`.
    static func parseVersion(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, line.count <= 200 else { continue }
            let containsDigit = line.contains { $0.isNumber }
            let isPrintable = line.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0)
            }
            if containsDigit && isPrintable {
                return String(line)
            }
        }
        return nil
    }
}

/// A `CLIProcessRunning` backed by Foundation `Process`. Reads output in bounded
/// chunks, enforces a hard timeout, and terminates the child on cooperative
/// cancellation. It never uses a shell: the caller-supplied absolute executable
/// is invoked directly.
///
/// Termination escalates: the child is first sent `SIGTERM`, and if it is still
/// running after a fixed grace period it is sent `SIGKILL`. This guarantees the
/// hard timeout is truly bounded even for a child that ignores `SIGTERM` or
/// keeps its pipes open. SIGKILL closes the child's pipe write ends, unblocking
/// the drain readers and `waitUntilExit`.
public struct DefaultCLIProcessRunner: CLIProcessRunning {
    private let killGracePeriod: Duration

    public init(killGracePeriod: Duration = .seconds(1)) {
        self.killGracePeriod = killGracePeriod
    }

    private final class ProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var escalated = false
        private let killQueue = DispatchQueue(label: "SafeCLIVersionProbe.kill")
        private let graceSeconds: Double

        init(graceSeconds: Double) {
            self.graceSeconds = graceSeconds
        }

        func store(_ process: Process) {
            lock.lock(); defer { lock.unlock() }
            self.process = process
        }

        /// Sends `SIGTERM` immediately, then escalates to `SIGKILL` after a
        /// fixed grace period if the *same* child is still running. Guarded by
        /// `isRunning` and object identity so a child that already exited (and
        /// whose PID may have been reused) is never signalled. Idempotent: the
        /// escalation is scheduled at most once.
        func terminate() {
            lock.lock()
            let proc = process
            let alreadyEscalated = escalated
            if !alreadyEscalated { escalated = true }
            lock.unlock()

            guard let proc, proc.isRunning, !alreadyEscalated else { return }
            proc.terminate() // SIGTERM

            killQueue.asyncAfter(deadline: .now() + graceSeconds) { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let current = self.process
                self.lock.unlock()
                // Only SIGKILL if it is still the same, still-running child.
                guard let current, current === proc, current.isRunning else { return }
                kill(current.processIdentifier, SIGKILL)
            }
        }
    }

    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> CLIProcessOutput {
        let box = ProcessBox(graceSeconds: killGracePeriod.seconds)
        let output = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLIProcessOutput, any Error>) in
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                process.environment = environment

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                box.store(process)

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timeoutFlag = TimeoutFlag()
                let queue = DispatchQueue(label: "SafeCLIVersionProbe.timeout")
                let deadline = DispatchTime.now() + timeout.seconds
                queue.asyncAfter(deadline: deadline) {
                    if process.isRunning {
                        timeoutFlag.markTimedOut()
                        // Route through the box so SIGTERM escalates to SIGKILL.
                        box.terminate()
                    }
                }

                DispatchQueue.global(qos: .utility).async {
                    // Drain stdout and stderr concurrently. Reading them
                    // serially can deadlock: if the child fills the stderr pipe
                    // while we are still blocked reading stdout (which waits for
                    // the child to exit), neither side can make progress. Each
                    // stream is capped independently but always drained to EOF.
                    let group = DispatchGroup()
                    let results = StreamResults()

                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let (data, truncated) = Self.readCapped(
                            outPipe.fileHandleForReading,
                            cap: maximumOutputBytes
                        )
                        results.setStandardOutput(data, truncated: truncated)
                        group.leave()
                    }

                    group.enter()
                    DispatchQueue.global(qos: .utility).async {
                        let (data, truncated) = Self.readCapped(
                            errPipe.fileHandleForReading,
                            cap: maximumOutputBytes
                        )
                        results.setStandardError(data, truncated: truncated)
                        group.leave()
                    }

                    group.wait()
                    process.waitUntilExit()
                    continuation.resume(returning: CLIProcessOutput(
                        standardOutput: results.standardOutput,
                        standardError: results.standardError,
                        terminationStatus: process.terminationStatus,
                        didTimeout: timeoutFlag.timedOut,
                        outputTruncated: results.truncated
                    ))
                }
            }
        } onCancel: {
            box.terminate()
        }
        // The continuation may resume with a completed output even though the
        // task was cancelled (the child was terminated but exited first). Make
        // cancellation authoritative so callers always observe CancellationError.
        try Task.checkCancellation()
        return output
    }

    private final class TimeoutFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        var timedOut: Bool {
            lock.lock(); defer { lock.unlock() }
            return value
        }
        func markTimedOut() {
            lock.lock(); defer { lock.unlock() }
            value = true
        }
    }

    /// Thread-safe accumulator for the two concurrently drained streams.
    private final class StreamResults: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        private var outTruncated = false
        private var errTruncated = false

        func setStandardOutput(_ data: Data, truncated: Bool) {
            lock.lock(); defer { lock.unlock() }
            out = data
            outTruncated = truncated
        }

        func setStandardError(_ data: Data, truncated: Bool) {
            lock.lock(); defer { lock.unlock() }
            err = data
            errTruncated = truncated
        }

        var standardOutput: Data {
            lock.lock(); defer { lock.unlock() }
            return out
        }

        var standardError: Data {
            lock.lock(); defer { lock.unlock() }
            return err
        }

        var truncated: Bool {
            lock.lock(); defer { lock.unlock() }
            return outTruncated || errTruncated
        }
    }

    private static func readCapped(
        _ handle: FileHandle,
        cap: Int
    ) -> (data: Data, truncated: Bool) {
        var data = Data()
        data.reserveCapacity(min(cap, 4096))
        while data.count < cap {
            let chunk = handle.readData(ofLength: min(4096, cap - data.count))
            if chunk.isEmpty { return (data, false) }
            data.append(chunk)
        }
        // Reached the cap. Drain the remainder in fixed small chunks so the
        // child is never blocked on a full pipe, but never accumulate it: an
        // adversarial flood stays bounded to `cap` bytes in memory.
        var truncated = false
        while true {
            let chunk = handle.readData(ofLength: 4096)
            if chunk.isEmpty { break }
            truncated = true
        }
        return (data, truncated)
    }
}

private extension Duration {
    /// The duration expressed in seconds as a `Double`, for Dispatch deadlines.
    var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

private struct VersionSortKey: Comparable, Equatable {
    let numericComponents: [Int]
    let fallback: String

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = trimmed.split(separator: ".").map(String.init)
        let parsed = parts.map { Int($0) }
        if !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) {
            self.numericComponents = parsed.map { $0 ?? 0 }
        } else {
            self.numericComponents = []
        }
        self.fallback = raw
    }

    static func < (lhs: VersionSortKey, rhs: VersionSortKey) -> Bool {
        if !lhs.numericComponents.isEmpty || !rhs.numericComponents.isEmpty {
            let count = max(lhs.numericComponents.count, rhs.numericComponents.count)
            for index in 0..<count {
                let lhsValue = index < lhs.numericComponents.count ? lhs.numericComponents[index] : 0
                let rhsValue = index < rhs.numericComponents.count ? rhs.numericComponents[index] : 0
                if lhsValue != rhsValue { return lhsValue < rhsValue }
            }
        }
        return lhs.fallback < rhs.fallback
    }
}

private extension URL {
    func hasPathComponentPrefix(_ prefix: URL) -> Bool {
        let components = pathComponents
        let prefixComponents = prefix.pathComponents
        guard prefixComponents.count <= components.count else { return false }
        return Array(components.prefix(prefixComponents.count)) == prefixComponents
    }
}
