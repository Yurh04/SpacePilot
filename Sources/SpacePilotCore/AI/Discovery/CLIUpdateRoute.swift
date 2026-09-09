import Foundation

/// Trusted package identities plus installation evidence. CLI-only Agents use
/// the same update pipeline as supporting CLIs, without assuming every binary
/// with the same name belongs to npm.
public struct CLIUpdateRoute: Sendable {
    public let capability: UpdateCapability?
    public let execution: UpdateExecutionCapability?

    private static let npmPackages: [String: String] = [
        "codex": "@openai/codex", "claude": "@anthropic-ai/claude-code",
        "gemini-cli": "@google/gemini-cli", "opencode": "opencode-ai",
        "copilot": "@github/copilot", "aiden": "@aiden-cli/core",
        "relay": "@bytedance-relay/claude-code", "pi": "@earendil-works/pi-coding-agent"
    ]

    public init(definition: AIToolDefinition, executableURL: URL) {
        let installed = executableURL.canonicalizedForDiscovery
        let path = installed.path
        var check = definition.updateCapability
        var manager: UpdateExecutionManager?
        var package = check?.packageIdentifier

        if let npm = Self.npmPackages[definition.id] {
            package = npm
            check = UpdateCapability(providerID: "npm", providerKind: .npmRegistry, packageIdentifier: npm)
            if path.contains("/node_modules/\(npm)/") {
                manager = path.contains("/pnpm/") ? .pnpm : .npm
            }
            if let basename = definition.cliProbeID,
               path.hasSuffix("/Library/pnpm/bin/\(basename)") {
                manager = .pnpm
            }
            if definition.id == "claude", path.contains("/.local/share/claude/versions/") {
                manager = .claudeNative
            }
        } else if ["aime", "mira", "aider"].contains(definition.id) {
            let pythonPackage = definition.id == "aider" ? "aider-chat" : "togo-cli"
            package = pythonPackage
            check = UpdateCapability(providerID: "pypi", providerKind: .pypi, packageIdentifier: pythonPackage)
            if path.contains("/uv/tools/\(pythonPackage)/bin/") {
                manager = .uv
            } else if path.contains("/pipx/venvs/\(pythonPackage)/bin/") {
                manager = .pipx
            }
        } else if definition.id == "ollama" {
            package = "ollama"
            check = UpdateCapability(providerID: "homebrew", providerKind: .homebrew, packageIdentifier: "ollama")
            if path.hasPrefix("/opt/homebrew/Cellar/ollama/") || path.hasPrefix("/usr/local/Cellar/ollama/") {
                manager = .homebrew
            }
        } else if let declared = definition.updateExecutionCapability {
            package = declared.packageIdentifier
            if path.contains("/node_modules/\(declared.packageIdentifier)/") {
                manager = declared.manager
            }
        }
        self.capability = check
        if let manager, let package {
            self.execution = UpdateExecutionCapability(
                manager: manager, packageIdentifier: package, installationURL: installed
            )
        } else {
            self.execution = nil
        }
    }
}
