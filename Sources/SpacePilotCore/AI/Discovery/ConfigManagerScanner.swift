import Foundation

/// Discovers configuration-manager tools — apps that manage an Agent's config,
/// credentials and Skills on the user's behalf (for example CC Switch, which
/// swaps Claude Code / Codex provider profiles and stores a `skills/` folder of
/// its own). They are not Agents and register no MCP server, so nothing else
/// finds them; without this they would not appear under "Other AI tools".
///
/// Design constraints, matching the other Core scanners:
///
/// - **Fixed table.** A tool is recognised only from a small definition table of
///   well-known managers (a home-relative config directory, and an optional app
///   bundle name). The disk is not walked and no name is inferred, so the scan
///   behaves identically on any machine.
/// - **Evidence-gated.** A manager is reported only when its config directory
///   actually exists on this machine — the presence of the directory *is* the
///   evidence, exactly as the config directory is for an Agent.
/// - **Read-only.** Only existence is checked; nothing is opened or executed.
public struct ConfigManagerScanner: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    /// One discovered configuration-manager tool.
    public struct Tool: Sendable, Equatable {
        public let name: String
        /// The manager's config directory (the stable, existing artifact). Used as
        /// the reveal target.
        public let url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    /// A well-known configuration manager and where its evidence lives.
    struct Known {
        let displayName: String
        /// Home-relative config directory whose existence proves the tool is set up.
        let configDirRelativePath: String
    }

    /// The recognised managers. Small and specific, like the Agent definition
    /// table: entries are added deliberately, never guessed from disk.
    static let known: [Known] = [
        Known(displayName: "CC Switch", configDirRelativePath: ".cc-switch")
    ]

    public func scan(homeDirectory: URL) -> [Tool] {
        var tools: [Tool] = []
        for entry in Self.known {
            let dir = homeDirectory.appending(path: entry.configDirRelativePath, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            tools.append(Tool(name: entry.displayName, url: dir.standardizedFileURL))
        }
        return tools.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
