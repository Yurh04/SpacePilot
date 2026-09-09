import Foundation

/// The outcome of a single executed update step.
public enum UpdateExecutionOutcome: Equatable, Sendable {
    /// Re-probe after execution confirmed the target version is installed.
    case succeeded(installedVersion: String)
    /// The manager could not be located as a verified fixed executable.
    case managerUnavailable
    /// The manager ran but exited non-zero.
    case failed(terminationStatus: Int32)
    /// The manager exceeded the per-item timeout.
    case timedOut
    /// The step was cancelled before or during execution.
    case cancelled
    /// The manager ran and exited zero, but the re-probe did not report the
    /// target version. Never reported as success.
    case versionMismatch(observed: String?)
}

/// The result of a single step, pairing the plan item with its outcome and a
/// redacted log summary.
public struct UpdateExecutionStepResult: Equatable, Sendable, Identifiable {
    public let key: AIUpdateAssetKey
    public let displayName: String
    public let targetVersion: String
    public let outcome: UpdateExecutionOutcome
    /// A redacted, single-line summary safe to show in the UI. Home paths,
    /// usernames, and token-like values are stripped upstream.
    public let logSummary: String

    public var id: AIUpdateAssetKey { key }

    public init(
        key: AIUpdateAssetKey,
        displayName: String,
        targetVersion: String,
        outcome: UpdateExecutionOutcome,
        logSummary: String
    ) {
        self.key = key
        self.displayName = displayName
        self.targetVersion = targetVersion
        self.outcome = outcome
        self.logSummary = logSummary
    }
}

/// Locates a package manager executable using only fixed, code-owned candidate
/// paths. Injected so tests provide a fake without touching the real machine.
public protocol UpdateManagerLocating: Sendable {
    /// Returns a verified, absolute executable for the manager, or `nil` when no
    /// fixed candidate exists and is executable. Never reads PATH or data.
    func locate(_ manager: UpdateExecutionManager) -> URL?
    func locate(_ manager: UpdateExecutionManager, installationURL: URL?, packageIdentifier: String) -> URL?
}

public extension UpdateManagerLocating {
    func locate(_ manager: UpdateExecutionManager, installationURL: URL?, packageIdentifier: String) -> URL? {
        locate(manager)
    }
}

/// Re-reads the installed version of a package after an update, using the same
/// safe, code-owned probing path as discovery. Injected for deterministic tests.
public protocol InstalledVersionProbing: Sendable {
    func installedVersion(
        manager: UpdateExecutionManager,
        packageIdentifier: String
    ) async -> String?
    func installedVersion(for item: UpdateExecutionPlan.Item) async -> String?
}

public extension InstalledVersionProbing {
    func installedVersion(for item: UpdateExecutionPlan.Item) async -> String? {
        await installedVersion(manager: item.manager, packageIdentifier: item.packageIdentifier)
    }
}

/// Production manager locator: fixed absolute candidates plus fixed
/// home-relative candidates. No PATH, no shell, no `/usr/bin/env`, no data.
public struct LocalUpdateManagerLocator: UpdateManagerLocating {
    private let homeDirectory: URL
    private let locator: any ExecutableLocating

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        locator: any ExecutableLocating = LocalExecutableLocator()
    ) {
        self.homeDirectory = homeDirectory
        self.locator = locator
    }

    // Fixed candidate paths per manager. These are code constants; nothing is
    // ever sourced from a manifest, receipt, config, or shell PATH.
    static let absoluteCandidates: [UpdateExecutionManager: [String]] = [
        .npm: ["/opt/homebrew/bin/npm", "/usr/local/bin/npm"],
        .pnpm: ["/opt/homebrew/bin/pnpm", "/usr/local/bin/pnpm"],
        .pipx: ["/opt/homebrew/bin/pipx", "/usr/local/bin/pipx"],
        .uv: ["/opt/homebrew/bin/uv", "/usr/local/bin/uv"],
        .homebrew: ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    ]

    static let homeRelativeCandidates: [UpdateExecutionManager: [String]] = [
        .pnpm: ["Library/pnpm/pnpm"],
        .pipx: [".local/bin/pipx"],
        .uv: [".local/bin/uv"]
    ]

    public func locate(_ manager: UpdateExecutionManager) -> URL? {
        for path in Self.absoluteCandidates[manager] ?? [] {
            let url = URL(fileURLWithPath: path)
            if locator.isExecutableFile(at: url) { return url }
        }
        for relative in Self.homeRelativeCandidates[manager] ?? [] {
            let url = homeDirectory.appending(path: relative)
            if locator.isExecutableFile(at: url) { return url }
        }
        return nil
    }

    public func locate(_ manager: UpdateExecutionManager, installationURL: URL?, packageIdentifier: String) -> URL? {
        guard let installationURL else { return locate(manager) }
        let path = installationURL.canonicalizedDiscoveryPath
        if manager == .npm {
            guard let prefix = Self.npmPrefix(path: path, package: packageIdentifier),
                  prefix == "/opt/homebrew" || prefix == "/usr/local"
                    || prefix.hasPrefix(homeDirectory.path + "/.local/share/fnm/node-versions/")
                    || prefix.hasPrefix(homeDirectory.path + "/.nvm/versions/node/") else { return nil }
            let npm = URL(fileURLWithPath: prefix + "/bin/npm")
            return locator.isExecutableFile(at: npm) ? npm : nil
        }
        if manager == .claudeNative {
            guard packageIdentifier == "@anthropic-ai/claude-code",
                  path.hasPrefix(homeDirectory.path + "/.local/share/claude/versions/"),
                  locator.isExecutableFile(at: installationURL) else { return nil }
            return installationURL
        }
        if manager == .homebrew {
            let prefix = path.hasPrefix("/opt/homebrew/Cellar/") ? "/opt/homebrew" : "/usr/local"
            guard path.hasPrefix(prefix + "/Cellar/\(packageIdentifier)/") else { return nil }
            let brew = URL(fileURLWithPath: prefix + "/bin/brew")
            return locator.isExecutableFile(at: brew) ? brew : nil
        }
        if manager == .uv && !path.contains("/uv/tools/\(packageIdentifier)/bin/") { return nil }
        if manager == .pipx && !path.contains("/pipx/venvs/\(packageIdentifier)/bin/") { return nil }
        if manager == .pnpm && !path.contains("/pnpm/") { return nil }
        return locate(manager)
    }

    static func npmPrefix(path: String, package: String) -> String? {
        guard let range = path.range(of: "/lib/node_modules/\(package)/") else { return nil }
        return String(path[..<range.lowerBound])
    }
}

/// Executes a user-confirmed `UpdateExecutionPlan` by running each fixed manager
/// executable directly (never a shell, never `/usr/bin/env`, never arbitrary
/// PATH), with a minimal fixed environment, per-item timeout, output cap, and
/// cooperative cancellation. After each step it re-probes the installed version
/// and only reports success when it matches the checked target. It performs no
/// automatic rollback and never fabricates success.
public struct AIUpdateExecutor: Sendable {
    private let runner: any CLIProcessRunning
    private let managerLocator: any UpdateManagerLocating
    private let versionProbe: any InstalledVersionProbing
    private let timeout: Duration
    private let maximumOutputBytes: Int
    private let homeDirectory: URL

    /// Minimal fixed environment. Only PATH (for the manager's own child
    /// lookups), HOME and TMPDIR are provided; no tokens, proxy, or inherited
    /// host environment. This is a code constant.
    static func fixedEnvironment(homeDirectory: URL) -> [String: String] {
        [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "HOME": homeDirectory.path,
            "TMPDIR": NSTemporaryDirectory()
        ]
    }

    static func environment(
        homeDirectory: URL, executable: URL,
        manager: UpdateExecutionManager, installationURL: URL?, package: String
    ) -> [String: String] {
        var env = fixedEnvironment(homeDirectory: homeDirectory)
        env["PATH"] = executable.deletingLastPathComponent().path + ":" + (env["PATH"] ?? "")
        guard let path = installationURL?.canonicalizedDiscoveryPath else { return env }
        if manager == .npm, let prefix = LocalUpdateManagerLocator.npmPrefix(path: path, package: package) {
            env["NPM_CONFIG_PREFIX"] = prefix
        }
        if manager == .uv, let range = path.range(of: "/uv/tools/\(package)/bin/") {
            env["UV_TOOL_DIR"] = String(path[..<range.lowerBound]) + "/uv/tools"
        }
        if manager == .pipx, let range = path.range(of: "/venvs/\(package)/bin/") {
            env["PIPX_HOME"] = String(path[..<range.lowerBound])
        }
        if manager == .pnpm, let range = path.range(of: "/Library/pnpm/") {
            let root = String(path[..<range.lowerBound]) + "/Library/pnpm"
            env["PNPM_HOME"] = root
        }
        return env
    }

    public init(
        runner: any CLIProcessRunning,
        managerLocator: any UpdateManagerLocating,
        versionProbe: any InstalledVersionProbing,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: Duration = .seconds(120),
        maximumOutputBytes: Int = 256 * 1_024
    ) {
        self.runner = runner
        self.managerLocator = managerLocator
        self.versionProbe = versionProbe
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    /// Runs each executable item sequentially. Stops early on cancellation; the
    /// remaining items are reported as `.cancelled`.
    public func execute(_ plan: UpdateExecutionPlan) async -> [UpdateExecutionStepResult] {
        var results: [UpdateExecutionStepResult] = []
        var cancelledRest = false
        for item in plan.executable {
            if cancelledRest || Task.isCancelled {
                results.append(step(item, outcome: .cancelled, log: "cancelled"))
                cancelledRest = true
                continue
            }
            let outcome = await runStep(item)
            if case .cancelled = outcome { cancelledRest = true }
            results.append(step(item, outcome: outcome, log: logSummary(for: outcome)))
        }
        return results
    }

    private func runStep(_ item: UpdateExecutionPlan.Item) async -> UpdateExecutionOutcome {
        guard VersionComparator.isValid(item.targetVersion, kind: item.manager.versionComparator),
              let executable = managerLocator.locate(
                item.manager, installationURL: item.installationURL, packageIdentifier: item.packageIdentifier
              ) else {
            return .managerUnavailable
        }
        let arguments = Self.arguments(
            manager: item.manager,
            packageIdentifier: item.packageIdentifier,
            targetVersion: item.targetVersion
        )
        let environment = Self.environment(
            homeDirectory: homeDirectory, executable: executable, manager: item.manager,
            installationURL: item.installationURL, package: item.packageIdentifier
        )
        do {
            let output = try await runner.run(
                executableURL: executable,
                arguments: arguments,
                environment: environment,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
            if output.didTimeout { return .timedOut }
            guard output.terminationStatus == 0 else {
                return .failed(terminationStatus: output.terminationStatus)
            }
            // Re-probe: success only if the installed version matches the target.
            let installed = await versionProbe.installedVersion(for: item)
            if let installed,
               VersionComparator.compare(installed, item.targetVersion, kind: item.manager.versionComparator) == .orderedSame {
                return .succeeded(installedVersion: installed)
            }
            return .versionMismatch(observed: installed)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(terminationStatus: -1)
        }
    }

    /// Fixed argument templates. Args are built only from the manager kind, the
    /// code-owned package identifier, and the already-validated target version.
    /// No argument is ever sourced from a manifest, receipt, or shell.
    static func arguments(
        manager: UpdateExecutionManager,
        packageIdentifier: String,
        targetVersion: String
    ) -> [String] {
        switch manager {
        case .npm:
            return ["install", "--global", "\(packageIdentifier)@\(targetVersion)"]
        case .pnpm:
            return ["add", "--global", "\(packageIdentifier)@\(targetVersion)"]
        case .pipx:
            return ["install", "--force", "\(packageIdentifier)==\(targetVersion)"]
        case .uv:
            return ["tool", "install", "--upgrade", "\(packageIdentifier)==\(targetVersion)"]
        case .homebrew:
            return ["upgrade", packageIdentifier]
        case .claudeNative:
            return ["install", targetVersion]
        }
    }

    private func step(
        _ item: UpdateExecutionPlan.Item,
        outcome: UpdateExecutionOutcome,
        log: String
    ) -> UpdateExecutionStepResult {
        UpdateExecutionStepResult(
            key: item.key,
            displayName: item.displayName,
            targetVersion: item.targetVersion,
            outcome: outcome,
            logSummary: log
        )
    }

    private func logSummary(for outcome: UpdateExecutionOutcome) -> String {
        switch outcome {
        case .succeeded(let installedVersion): "installed \(installedVersion)"
        case .managerUnavailable: "manager unavailable"
        case .failed(let status): "failed (exit \(status))"
        case .timedOut: "timed out"
        case .cancelled: "cancelled"
        case .versionMismatch(let observed): "version mismatch (observed \(observed ?? "none"))"
        }
    }
}
