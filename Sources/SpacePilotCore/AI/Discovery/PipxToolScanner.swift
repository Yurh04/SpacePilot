import Foundation

/// Discovers standalone tools installed by Python tool managers (pipx and
/// `uv tool`) so they surface under "Other AI tools" rather than vanishing —
/// they are not on any Agent's CLI probe template and register no MCP server,
/// so nothing else would find them.
///
/// Design constraints, matching the other Core scanners:
///
/// - **Fixed locations.** Only the well-known pipx/uv venv roots under the home
///   directory are enumerated. The disk is not walked, so an unrelated tree can
///   never pull the scan somewhere unexpected.
/// - **Read-only.** Directory names are listed; nothing is opened or executed.
/// - **Every managed tool, minus common noise.** Each venv directory is one
///   installed tool, so all are listed. A small deny-list drops well-known
///   general-purpose Python dev tools (formatters, linters, packaging) that are
///   not AI-adjacent, so the list stays meaningful on any machine without a
///   fragile keyword allow-list that would miss new AI tools.
public struct PipxToolScanner: Sendable {
    public init() {}

    private var fileManager: FileManager { .default }

    /// One discovered Python-managed tool.
    public struct Tool: Sendable, Equatable {
        public let name: String
        /// The tool's venv directory (the stable, existing artifact). Used as the
        /// reveal target and the install-source signal.
        public let url: URL

        public init(name: String, url: URL) {
            self.name = name
            self.url = url
        }
    }

    /// Home-relative roots that hold one sub-directory per installed tool. Both
    /// pipx layouts (the newer `Library/Application Support` and the older
    /// `.local/pipx`) and the `uv tool` root are covered.
    static let venvRootRelativePaths = [
        "Library/Application Support/pipx/venvs",
        ".local/pipx/venvs",
        ".local/share/uv/tools"
    ]

    /// Well-known general-purpose Python dev tools that are not AI-adjacent.
    /// Compared case-insensitively against the venv name. Deliberately small and
    /// specific: it removes obvious noise without risking a real AI tool.
    static let excludedToolNames: Set<String> = [
        "black", "ruff", "flake8", "mypy", "pylint", "isort", "poetry",
        "pipenv", "pre-commit", "tox", "twine", "cookiecutter", "virtualenv",
        "hatch", "pdm", "pipx", "yt-dlp", "httpie", "pip-tools"
    ]

    public func scan(homeDirectory: URL) -> [Tool] {
        var tools: [Tool] = []
        var seenNames: Set<String> = []
        for relative in Self.venvRootRelativePaths {
            let root = homeDirectory.appending(path: relative)
            guard let entries = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for entry in entries {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = entry.lastPathComponent
                guard !Self.excludedToolNames.contains(name.lowercased()) else { continue }
                // A tool installed under two managers is listed once.
                guard seenNames.insert(name.lowercased()).inserted else { continue }
                tools.append(Tool(name: name, url: entry.standardizedFileURL))
            }
        }
        return tools.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
