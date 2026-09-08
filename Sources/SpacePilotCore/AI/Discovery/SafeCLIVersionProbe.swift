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
    /// Resolves a candidate to its canonical executable (following symlinks).
    /// Used to prove that a generic bin candidate belongs to an expected npm
    /// package. Defaults to real filesystem resolution.
    func canonicalExecutable(at url: URL) -> URL
    /// Whether a directory exists at `url`. Used to confirm a
    /// `node_modules/<packageID>` install. Defaults to a real filesystem check.
    func directoryExists(at url: URL) -> Bool
}

public extension ExecutableLocating {
    func canonicalExecutable(at url: URL) -> URL { url.canonicalizedForDiscovery }

    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }
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
    /// Fixed, code-owned alias paths that resolve to the *same* canonical
    /// executable as `executableURL` (for example `trae-cli` / `trae-agent`
    /// pointing at `traex`). Surfaced as read-only evidence; never executed
    /// separately and never turned into a second CLI record.
    public let aliasExecutableURLs: [URL]

    public init(
        executableURL: URL?,
        version: String?,
        coverageFailure: AIToolCoverageFailure?,
        aliasExecutableURLs: [URL] = []
    ) {
        self.executableURL = executableURL
        self.version = version
        self.coverageFailure = coverageFailure
        self.aliasExecutableURLs = aliasExecutableURLs
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
        /// Fixed `uv` tool package names. Each expands to the code-owned template
        /// `~/.local/share/uv/tools/<package>/bin/<basename>`; the package token
        /// is a definition constant, never read from a manifest or shell.
        let uvToolPackages: [String]
        /// Fixed npm package identifiers (for example `@openai/codex`,
        /// `@dp/one-cli`, `botmux`) installed under a Node manager version root.
        /// A FNM/NVM `installation/bin/<basename>` (or `bin/<basename>`) candidate
        /// is only accepted when the *same* version root also contains
        /// `.../lib/node_modules/<packageID>`. This proves the executable belongs
        /// to the expected published package instead of trusting any file that
        /// merely shares the basename. The identifier is a code constant; it is
        /// never read from a manifest, receipt, or shell. Empty means the tool
        /// is not distributed via a Node manager and gets no FNM/NVM candidate.
        let nodePackageIdentifiers: [String]
        /// Fixed alias basenames that resolve (via canonical symlink resolution)
        /// to the same executable as the primary candidate. Used as read-only
        /// evidence only; never executed independently.
        let aliasBasenames: [String]
        /// Fixed arguments used to request the version (for example `--version`).
        let versionArguments: [String]

        init(
            basename: String,
            absoluteCandidatePaths: [String],
            homeRelativeCandidatePaths: [String],
            appBundledAbsoluteCandidatePaths: [String] = [],
            uvToolPackages: [String] = [],
            nodePackageIdentifiers: [String] = [],
            aliasBasenames: [String] = [],
            versionArguments: [String]
        ) {
            self.basename = basename
            self.absoluteCandidatePaths = absoluteCandidatePaths
            self.homeRelativeCandidatePaths = homeRelativeCandidatePaths
            self.appBundledAbsoluteCandidatePaths = appBundledAbsoluteCandidatePaths
            self.uvToolPackages = uvToolPackages
            self.nodePackageIdentifiers = nodePackageIdentifiers
            self.aliasBasenames = aliasBasenames
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
            nodePackageIdentifiers: ["@openai/codex"],
            versionArguments: ["--version"]
        ),
        "claude": ProbeSpec(
            basename: "claude",
            absoluteCandidatePaths: ["/usr/local/bin/claude", "/opt/homebrew/bin/claude"],
            homeRelativeCandidatePaths: [".local/bin/claude"],
            nodePackageIdentifiers: ["@anthropic-ai/claude-code"],
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
            nodePackageIdentifiers: ["@google/gemini-cli"],
            versionArguments: ["--version"]
        ),
        "opencode": ProbeSpec(
            basename: "opencode",
            absoluteCandidatePaths: ["/usr/local/bin/opencode", "/opt/homebrew/bin/opencode"],
            homeRelativeCandidatePaths: [".local/bin/opencode"],
            nodePackageIdentifiers: ["opencode-ai"],
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
        ),
        // ByteDance / third-party CLIs confirmed on the target machine. All are
        // resolved through fixed, code-owned templates (FNM node-versions, uv
        // tool roots, Homebrew, or an exact home-relative install path). None
        // read the shell PATH or a package manifest.
        "merlin-cli": ProbeSpec(
            basename: "merlin-cli",
            absoluteCandidatePaths: [],
            homeRelativeCandidatePaths: [".merlin-cli/bin/merlin-cli"],
            versionArguments: ["--version"]
        ),
        "one": ProbeSpec(
            basename: "one",
            absoluteCandidatePaths: ["/usr/local/bin/one", "/opt/homebrew/bin/one"],
            homeRelativeCandidatePaths: [".local/bin/one"],
            nodePackageIdentifiers: ["@dp/one-cli"],
            versionArguments: ["--version"]
        ),
        "bytedcli": ProbeSpec(
            basename: "bytedcli",
            absoluteCandidatePaths: ["/usr/local/bin/bytedcli", "/opt/homebrew/bin/bytedcli"],
            homeRelativeCandidatePaths: [".local/bin/bytedcli"],
            nodePackageIdentifiers: ["@bytedance-dev/bytedcli"],
            versionArguments: ["--version"]
        ),
        "opencli": ProbeSpec(
            basename: "opencli",
            absoluteCandidatePaths: ["/usr/local/bin/opencli", "/opt/homebrew/bin/opencli"],
            homeRelativeCandidatePaths: [".local/bin/opencli"],
            nodePackageIdentifiers: ["@jackwener/opencli"],
            versionArguments: ["--version"]
        ),
        "botmux": ProbeSpec(
            basename: "botmux",
            absoluteCandidatePaths: ["/usr/local/bin/botmux", "/opt/homebrew/bin/botmux"],
            homeRelativeCandidatePaths: [".local/bin/botmux"],
            nodePackageIdentifiers: ["botmux"],
            versionArguments: ["--version"]
        ),
        "traex": ProbeSpec(
            basename: "traex",
            absoluteCandidatePaths: [],
            homeRelativeCandidatePaths: [".local/share/traex/current/traex"],
            aliasBasenames: ["trae-cli", "trae-agent"],
            versionArguments: ["--version"]
        ),
        "lark-cli": ProbeSpec(
            basename: "lark-cli",
            absoluteCandidatePaths: ["/opt/homebrew/bin/lark-cli", "/usr/local/bin/lark-cli"],
            homeRelativeCandidatePaths: [".local/bin/lark-cli"],
            versionArguments: ["--version"]
        ),
        "aime": ProbeSpec(
            basename: "aime",
            absoluteCandidatePaths: [],
            homeRelativeCandidatePaths: [".local/bin/aime"],
            uvToolPackages: ["togo-cli"],
            versionArguments: ["--version"]
        ),
        "mira": ProbeSpec(
            basename: "mira",
            absoluteCandidatePaths: [],
            homeRelativeCandidatePaths: [".local/bin/mira"],
            uvToolPackages: ["togo-cli"],
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

        // Fixed alias basenames (for example `trae-cli` / `trae-agent`) that
        // canonically resolve to the *same* executable are surfaced as read-only
        // evidence so the UI shows one CLI with its known aliases instead of
        // duplicate rows. They are never executed independently.
        let aliasURLs = resolvedAliasEvidence(
            for: spec,
            primary: candidate.executableURL,
            homeDirectory: homeDirectory
        )

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
                coverageFailure: .unavailable,
                aliasExecutableURLs: aliasURLs
            )
        }

        // The runner terminates the child on cancellation but may still return a
        // completed output; make cancellation authoritative here.
        try Task.checkCancellation()

        if output.didTimeout {
            return SafeCLIProbeResult(
                executableURL: candidate.executableURL,
                version: nil,
                coverageFailure: .timeout,
                aliasExecutableURLs: aliasURLs
            )
        }

        let parsed = Self.parseVersion(from: output.standardOutput)
            ?? Self.parseVersion(from: output.standardError)

        if output.terminationStatus != 0 || parsed == nil {
            return SafeCLIProbeResult(
                executableURL: candidate.executableURL,
                version: parsed,
                coverageFailure: .invalidOutput,
                aliasExecutableURLs: aliasURLs
            )
        }

        return SafeCLIProbeResult(
            executableURL: candidate.executableURL,
            version: parsed,
            coverageFailure: output.outputTruncated ? .outputTruncated : nil,
            aliasExecutableURLs: aliasURLs
        )
    }

    /// Resolves the fixed alias basenames for a spec, keeping only those that
    /// canonically resolve to the same executable as the primary candidate. The
    /// alias search location is a code constant (`~/.local/bin/<alias>`); nothing
    /// is read from PATH or a manifest. The returned URLs are the alias paths as
    /// declared (pre-resolution) so the UI can show the alias name the user
    /// knows, deduplicated and deterministically ordered.
    private func resolvedAliasEvidence(
        for spec: ProbeSpec,
        primary: URL,
        homeDirectory: URL
    ) -> [URL] {
        guard !spec.aliasBasenames.isEmpty else { return [] }
        let canonicalPrimary = primary.standardizedFileURL.resolvingSymlinksInPath().path
        var seen = Set<String>()
        var result: [URL] = []
        for alias in spec.aliasBasenames.sorted() {
            let aliasURL = homeDirectory.appending(
                path: ".local/bin/\(alias)",
                directoryHint: .notDirectory
            )
            guard locator.isExecutableFile(at: aliasURL) else { continue }
            let canonicalAlias = aliasURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard canonicalAlias == canonicalPrimary else { continue }
            if seen.insert(aliasURL.standardizedFileURL.path).inserted {
                result.append(aliasURL)
            }
        }
        return result
    }

    private func probeCandidates(for spec: ProbeSpec, homeDirectory: URL) -> [ProbeCandidate] {
        var candidates: [ProbeCandidate] = []
        // Generic basename candidates (fixed absolute dirs, ~/.local/bin, and the
        // pnpm global bin) carry no package identity, so any executable that
        // merely shares the basename would be executed and attributed. They are
        // only allowed for tools that are NOT distributed as a known npm package.
        // Node-package tools must instead be resolved through the package-ID
        // gated FNM/NVM/uv manager templates (plus fixed app-bundled exact paths)
        // below, so `/usr/local/bin/one`, `~/.local/bin/one`, and
        // `~/Library/pnpm/bin/one` never bypass the `@dp/one-cli` check.
        if spec.nodePackageIdentifiers.isEmpty {
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
        } else {
            // A node-package tool installed via Homebrew or `npm -g` is exposed as
            // a symlink in `/usr/local/bin`, `/opt/homebrew/bin`, `~/.local/bin`,
            // or the pnpm bin. Those generic locations carry no package identity on
            // their own, so a candidate is admitted only when its symlink resolves
            // into a `node_modules/<packageID>` install for one of the fixed
            // identifiers — the same "prove the package is installed" invariant the
            // FNM/NVM branch enforces, just for a symlinked global install. An
            // unrelated binary that merely shares the basename is never accepted.
            var identityGated: [URL] = spec.absoluteCandidatePaths.map { URL(filePath: $0) }
            identityGated.append(contentsOf: spec.homeRelativeCandidatePaths.map {
                homeDirectory.appending(path: $0, directoryHint: .notDirectory)
            })
            identityGated.append(
                homeDirectory.appending(path: "Library/pnpm/bin/\(spec.basename)", directoryHint: .notDirectory)
            )
            for candidateURL in identityGated {
                guard let verified = nodePackageCandidate(
                    at: candidateURL,
                    requiredPackageIdentifiers: spec.nodePackageIdentifiers
                ) else { continue }
                candidates.append(verified)
            }
        }
        // FNM/NVM candidates are only offered for tools distributed as a known
        // npm package. Each candidate is accepted only when its own version root
        // also contains `.../lib/node_modules/<packageID>` for one of the fixed
        // identifiers, so a random executable that merely shares the basename in
        // some Node version's bin directory is never executed or attributed.
        if !spec.nodePackageIdentifiers.isEmpty {
            candidates.append(contentsOf: versionedManagerCandidates(
                homeDirectory: homeDirectory,
                managerRootRelativePath: ".local/share/fnm/node-versions",
                executableTail: "installation/bin/\(spec.basename)",
                nodeModulesTail: "installation/lib/node_modules",
                requiredPackageIdentifiers: spec.nodePackageIdentifiers
            ))
            candidates.append(contentsOf: versionedManagerCandidates(
                homeDirectory: homeDirectory,
                managerRootRelativePath: ".nvm/versions/node",
                executableTail: "bin/\(spec.basename)",
                nodeModulesTail: "lib/node_modules",
                requiredPackageIdentifiers: spec.nodePackageIdentifiers
            ))
        }
        // Fixed `uv` tool layout: ~/.local/share/uv/tools/<package>/bin/<basename>.
        // Both the package token and the basename are definition constants. The
        // canonical tool root must stay inside the canonical uv tools manager
        // root (rejecting a symlinked package dir that escapes the tree), and
        // the canonical executable must stay inside that tool root.
        if !spec.uvToolPackages.isEmpty {
            let uvToolsRoot = homeDirectory
                .appending(path: ".local/share/uv/tools", directoryHint: .isDirectory)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            for package in spec.uvToolPackages {
                let toolRoot = uvToolsRoot
                    .appending(path: package, directoryHint: .isDirectory)
                    .standardizedFileURL
                    .resolvingSymlinksInPath()
                guard toolRoot.hasPathComponentPrefix(uvToolsRoot) else { continue }
                let executableURL = toolRoot.appending(path: "bin/\(spec.basename)", directoryHint: .notDirectory)
                let canonicalExecutable = executableURL.standardizedFileURL.resolvingSymlinksInPath()
                guard canonicalExecutable.hasPathComponentPrefix(toolRoot) else { continue }
                candidates.append(ProbeCandidate(
                    executableURL: canonicalExecutable,
                    environment: Self.fixedEnvironment
                ))
            }
        }
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
        executableTail: String,
        nodeModulesTail: String,
        requiredPackageIdentifiers: [String]
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
            // Require that this version root actually installed one of the fixed
            // npm packages. Without this the probe would run any executable that
            // merely shares the basename in a Node version's bin directory and
            // attribute it to the AI tool. The node_modules root is kept inside
            // the version directory (symlink escape rejected) before it is used.
            guard Self.versionRootInstalledExpectedPackage(
                canonicalVersionDirectory: canonicalVersionDirectory,
                nodeModulesTail: nodeModulesTail,
                requiredPackageIdentifiers: requiredPackageIdentifiers
            ) else {
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

    /// Returns true when the Node version root contains an installed package
    /// directory for one of the fixed identifiers under its `node_modules`. A
    /// scoped identifier such as `@openai/codex` is resolved a component at a
    /// time and the canonical package directory must stay inside the version
    /// root's `node_modules`, so a symlinked package that escapes the tree is
    /// rejected. Only directory existence is checked; nothing is read or run.
    private static func versionRootInstalledExpectedPackage(
        canonicalVersionDirectory: URL,
        nodeModulesTail: String,
        requiredPackageIdentifiers: [String]
    ) -> Bool {
        let nodeModulesRoot = canonicalVersionDirectory
            .appending(path: nodeModulesTail, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard nodeModulesRoot.hasPathComponentPrefix(canonicalVersionDirectory) else { return false }
        for identifier in requiredPackageIdentifiers {
            var packageURL = nodeModulesRoot
            for component in identifier.split(separator: "/", omittingEmptySubsequences: true) {
                packageURL = packageURL.appending(path: String(component), directoryHint: .isDirectory)
            }
            let canonicalPackage = packageURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalPackage.hasPathComponentPrefix(nodeModulesRoot) else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: canonicalPackage.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return true
            }
        }
        return false
    }

    private static func environment(prependingVerifiedBin bin: URL) -> [String: String] {
        var environment = fixedEnvironment
        environment["PATH"] = bin.path + ":" + (fixedEnvironment["PATH"] ?? "")
        return environment
    }

    /// Verifies a generic bin candidate (Homebrew / npm-global / pnpm) for a
    /// node-package tool by resolving its symlink and confirming the resolved
    /// executable lives inside a `node_modules/<packageID>` install for one of the
    /// fixed identifiers. This gives the generic location the same package
    /// identity the FNM/NVM branch requires, so an unrelated same-named binary is
    /// never executed or attributed. All filesystem access goes through the
    /// injected `locator`, keeping the check deterministic under test. Returns
    /// `nil` when the candidate is missing, not executable, or cannot be tied to
    /// an expected package.
    private func nodePackageCandidate(
        at candidateURL: URL,
        requiredPackageIdentifiers: [String]
    ) -> ProbeCandidate? {
        guard locator.isExecutableFile(at: candidateURL) else { return nil }
        let canonicalExecutable = locator.canonicalExecutable(at: candidateURL)
        // Walk up from the resolved executable looking for a `node_modules`
        // directory that contains one of the expected package directories. A
        // typical layout is `.../node_modules/<packageID>/{bin,dist}/cli.js` with
        // the bin symlinked into a generic location.
        var directory = canonicalExecutable.deletingLastPathComponent()
        var depth = 0
        while depth < 12, directory.path != "/" {
            if directory.lastPathComponent == "node_modules" {
                for identifier in requiredPackageIdentifiers {
                    var packageURL = directory
                    for component in identifier.split(separator: "/", omittingEmptySubsequences: true) {
                        packageURL = packageURL.appending(path: String(component), directoryHint: .isDirectory)
                    }
                    guard packageURL.hasPathComponentPrefix(directory),
                          canonicalExecutable.hasPathComponentPrefix(directory),
                          locator.directoryExists(at: packageURL) else { continue }
                    return ProbeCandidate(
                        executableURL: canonicalExecutable,
                        environment: Self.fixedEnvironment
                    )
                }
            }
            directory = directory.deletingLastPathComponent()
            depth += 1
        }
        return nil
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
