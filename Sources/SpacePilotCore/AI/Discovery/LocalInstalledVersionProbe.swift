import Foundation

/// Re-reads the installed version of a package after an update by invoking the
/// same fixed manager executable that performed the install, with a fixed,
/// code-owned "list" argument template. It never runs a shell, `/usr/bin/env`,
/// or an arbitrary PATH, and it parses only the manager's own machine-readable
/// output — no manifest, receipt, or config is consulted. Injected so the
/// executor can be exercised without touching the real machine.
public struct LocalInstalledVersionProbe: InstalledVersionProbing {
    private let runner: any CLIProcessRunning
    private let managerLocator: any UpdateManagerLocating
    private let homeDirectory: URL
    private let timeout: Duration
    private let maximumOutputBytes: Int

    public init(
        runner: any CLIProcessRunning = DefaultCLIProcessRunner(),
        managerLocator: any UpdateManagerLocating = LocalUpdateManagerLocator(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: Duration = .seconds(15),
        maximumOutputBytes: Int = 256 * 1_024
    ) {
        self.runner = runner
        self.managerLocator = managerLocator
        self.homeDirectory = homeDirectory
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
    }

    /// Fixed, code-owned list-argument templates. Every argument is a constant;
    /// the package identifier is the same trusted constant used to install.
    static func listArguments(
        manager: UpdateExecutionManager,
        packageIdentifier: String
    ) -> [String] {
        switch manager {
        case .npm:
            return ["ls", "--global", "--depth", "0", packageIdentifier]
        case .pnpm:
            return ["ls", "--global"]
        case .pipx:
            return ["list", "--short"]
        }
    }

    public func installedVersion(
        manager: UpdateExecutionManager,
        packageIdentifier: String
    ) async -> String? {
        guard let executable = managerLocator.locate(manager) else { return nil }
        let arguments = Self.listArguments(manager: manager, packageIdentifier: packageIdentifier)
        let environment = AIUpdateExecutor.fixedEnvironment(homeDirectory: homeDirectory)
        do {
            let output = try await runner.run(
                executableURL: executable,
                arguments: arguments,
                environment: environment,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
            guard !output.didTimeout, output.terminationStatus == 0 else { return nil }
            let text = (String(data: output.standardOutput, encoding: .utf8) ?? "")
                + "\n"
                + (String(data: output.standardError, encoding: .utf8) ?? "")
            return Self.parseVersion(from: text, packageIdentifier: packageIdentifier)
        } catch {
            return nil
        }
    }

    /// Parses "<package>@<version>" or "<package> <version>" occurrences from a
    /// manager listing, returning the first version associated with the exact
    /// package identifier. Only trusted constant package identifiers are matched.
    static func parseVersion(from text: String, packageIdentifier: String) -> String? {
        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            // "name@version" (npm/pnpm) — the package identifier may itself
            // contain a scope "@scope/name", so match on the LAST "@".
            if line.contains(packageIdentifier) {
                let scanned = scanTrailingVersion(line: line, packageIdentifier: packageIdentifier)
                if let scanned { return scanned }
            }
        }
        return nil
    }

    private static func scanTrailingVersion(line: String, packageIdentifier: String) -> String? {
        // Find "<packageIdentifier>@<version>" first.
        if let range = line.range(of: packageIdentifier + "@") {
            let rest = line[range.upperBound...]
            let token = rest.prefix { !$0.isWhitespace }
            let candidate = String(token)
            if SemVerComparator.compare(candidate, candidate) != nil { return candidate }
        }
        // Fallback "<packageIdentifier> <version>" (pipx --short style).
        if let range = line.range(of: packageIdentifier) {
            let rest = line[range.upperBound...].drop { $0.isWhitespace }
            let token = rest.prefix { !$0.isWhitespace }
            let candidate = String(token)
            if SemVerComparator.compare(candidate, candidate) != nil { return candidate }
        }
        return nil
    }
}
