import Foundation

/// The first batch of known AI tool definitions.
///
/// This is intentionally a *pure data table*: adding or adjusting a tool means
/// editing this list only, never the registry engine. Probe identifiers here
/// must match a whitelist entry in `SafeCLIVersionProbe`; unknown probe IDs are
/// rejected at probe time and never spawn a process.
///
/// `~/.agents/skills` is declared as a `.shared` skill root on every tool that
/// can consume it; the registry collapses those into a single `owner: .shared`
/// record so a shared directory is never double-counted per tool.
public enum KnownAIToolDefinitions {
    /// A shared, cross-agent skills directory owned by no single tool.
    static let sharedAgentsSkillsRoot = AIToolRootDescriptor(
        ".agents/skills",
        ownership: .shared,
        displayNameOverride: "Shared Agent Skills"
    )

    static let sharedProjectSkills = AIProjectAssetDescriptor(
        ".agents/skills",
        ownership: .shared,
        kind: .skills
    )

    // MARK: - Agent classification helpers

    /// A local AI Agent (has a local runtime/client operating on the workspace).
    static func localAgent(
        _ formFactors: Set<AIAgentFormFactor>,
        symbol: String
    ) -> AIAgentProfile {
        AIAgentProfile(locality: .local, formFactors: formFactors, fallbackSymbolName: symbol)
    }

    /// A remote/cloud AI Agent. Detected only through the definition's fixed
    /// local account/client/config evidence; typically has no local storage,
    /// skills, or plugins to manage.
    static func remoteAgent(
        _ formFactors: Set<AIAgentFormFactor> = [.cloud],
        symbol: String = "cloud"
    ) -> AIAgentProfile {
        AIAgentProfile(locality: .remote, formFactors: formFactors, fallbackSymbolName: symbol)
    }

    public static let all: [AIToolDefinition] = [
        AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            // Codex is a CLI / npm package. The `com.openai.codex` bundle ID
            // belongs to the ChatGPT desktop app (owned by the `chatgpt`
            // definition), so Codex claims no application bundle here.
            dataRootRelativePaths: [".codex"],
            skillRoots: [AIToolRootDescriptor(".codex/skills"), sharedAgentsSkillsRoot],
            pluginRoots: [AIToolRootDescriptor(".codex/plugins")],
            configRelativePaths: [".codex"],
            cliProbeID: "codex",
            packageDescriptors: [
                AIToolPackageDescriptor(
                    manager: .npm,
                    packageName: "@openai/codex",
                    metadataRelativePaths: [".npm/_spacepilot/receipts/@openai/codex/package.json"]
                ),
                AIToolPackageDescriptor(
                    manager: .pnpm,
                    packageName: "@openai/codex",
                    metadataRelativePaths: [".local/share/pnpm/global/5/node_modules/@openai/codex/package.json"]
                )
            ],
            updateCapability: UpdateCapability(
                providerID: "npm",
                providerKind: .npmRegistry,
                packageIdentifier: "@openai/codex"
            ),
            updateExecutionCapability: UpdateExecutionCapability(
                manager: .npm,
                packageIdentifier: "@openai/codex"
            ),
            projectAssetDescriptors: [
                AIProjectAssetDescriptor(".codex/skills", kind: .skills),
                AIProjectAssetDescriptor(".codex/plugins", kind: .pluginContainer),
                sharedProjectSkills
            ],
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        AIToolDefinition(
            id: "claude",
            displayName: "Claude",
            applicationBundleIdentifiers: ["com.anthropic.claudefordesktop"],
            dataRootRelativePaths: [".claude"],
            skillRoots: [AIToolRootDescriptor(".claude/skills"), sharedAgentsSkillsRoot],
            pluginRoots: [AIToolRootDescriptor(".claude/plugins")],
            configRelativePaths: [".claude"],
            cliProbeID: "claude",
            projectAssetDescriptors: [
                AIProjectAssetDescriptor(".claude/skills", kind: .skills),
                AIProjectAssetDescriptor(".claude/plugins", kind: .pluginContainer),
                sharedProjectSkills
            ],
            agentProfile: localAgent([.application, .cli], symbol: "sparkles")
        ),
        AIToolDefinition(
            id: "chatgpt",
            displayName: "ChatGPT",
            applicationBundleIdentifiers: ["com.openai.codex"],
            dataRootRelativePaths: [],
            configRelativePaths: [],
            agentProfile: localAgent([.application], symbol: "bubble.left.and.bubble.right")
        ),
        AIToolDefinition(
            id: "cursor",
            displayName: "Cursor",
            applicationBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            dataRootRelativePaths: [".cursor"],
            configRelativePaths: [".cursor"],
            cliProbeID: "cursor",
            agentProfile: localAgent([.application, .cli], symbol: "cursorarrow.rays")
        ),
        AIToolDefinition(
            id: "trae-cn",
            displayName: "Trae CN",
            applicationBundleIdentifiers: ["cn.trae.app"],
            dataRootRelativePaths: [".trae"],
            skillRoots: [
                AIToolRootDescriptor(".trae/skills"),
                AIToolRootDescriptor(
                    ".trae-cn/builtin_skills",
                    displayNameOverride: "Trae CN"
                ),
                AIToolRootDescriptor(
                    ".trae-cn/builtin/global/skills",
                    displayNameOverride: "Trae CN"
                ),
                AIToolRootDescriptor(
                    ".trae-cn/skills",
                    displayNameOverride: "Trae CN"
                )
            ],
            pluginRoots: [
                AIToolRootDescriptor(".trae-cn/plugins/trae-remote-official")
            ],
            configRelativePaths: [".trae", ".trae-cn"],
            cliProbeID: "trae",
            agentProfile: localAgent([.application, .cli], symbol: "sparkles.rectangle.stack")
        ),
        AIToolDefinition(
            id: "trae-solo-cn",
            displayName: "TRAE SOLO CN",
            applicationBundleIdentifiers: ["cn.trae.solo.app"],
            dataRootRelativePaths: [".trae-solo", ".traework"],
            configRelativePaths: [".trae-solo", ".traework"],
            cliProbeID: "traework",
            agentProfile: localAgent([.application, .cli], symbol: "sparkles.rectangle.stack")
        ),
        AIToolDefinition(
            id: "antigravity",
            displayName: "Antigravity",
            applicationBundleIdentifiers: ["com.google.antigravity"],
            dataRootRelativePaths: [".antigravity"],
            configRelativePaths: [".antigravity"],
            cliProbeID: "antigravity",
            agentProfile: localAgent([.application, .cli], symbol: "circle.hexagongrid")
        ),
        AIToolDefinition(
            id: "vscode",
            displayName: "Visual Studio Code",
            applicationBundleIdentifiers: ["com.microsoft.VSCode"],
            configRelativePaths: [
                "Library/Application Support/Code/User/globalStorage/github.copilot-chat",
                "Library/Application Support/Code/User/globalStorage/continue.continue",
                "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev",
                "Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline"
            ],
            hostEvidenceRelativePaths: [
                ".vscode/extensions/github.copilot-chat",
                ".vscode/extensions/continue.continue",
                ".vscode/extensions/saoudrizwan.claude-dev",
                ".vscode/extensions/rooveterinaryinc.roo-cline",
                "Library/Application Support/Code/User/globalStorage/github.copilot-chat",
                "Library/Application Support/Code/User/globalStorage/continue.continue",
                "Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev",
                "Library/Application Support/Code/User/globalStorage/rooveterinaryinc.roo-cline"
            ],
            agentProfile: localAgent([.application], symbol: "chevron.left.forwardslash.chevron.right")
        ),
        AIToolDefinition(
            id: "windsurf",
            displayName: "Windsurf",
            applicationBundleIdentifiers: ["com.exafunction.windsurf"],
            dataRootRelativePaths: [".windsurf", ".codeium"],
            configRelativePaths: [".windsurf"],
            cliProbeID: "windsurf",
            agentProfile: localAgent([.application, .cli], symbol: "wind")
        ),
        AIToolDefinition(
            id: "gemini-cli",
            displayName: "Gemini CLI",
            dataRootRelativePaths: [".gemini"],
            configRelativePaths: [".gemini"],
            cliProbeID: "gemini",
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        AIToolDefinition(
            id: "opencode",
            displayName: "OpenCode",
            dataRootRelativePaths: [".opencode", ".config/opencode"],
            configRelativePaths: [".config/opencode"],
            cliProbeID: "opencode",
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        AIToolDefinition(
            id: "aider",
            displayName: "Aider",
            dataRootRelativePaths: [".aider"],
            configRelativePaths: [".aider"],
            cliProbeID: "aider",
            packageDescriptors: [
                AIToolPackageDescriptor(
                    manager: .pipx,
                    packageName: "aider-chat",
                    metadataRelativePaths: [".local/pipx/venvs/aider-chat/pipx_metadata.json"]
                )
            ],
            updateCapability: UpdateCapability(
                providerID: "pypi",
                providerKind: .pypi,
                packageIdentifier: "aider-chat"
            ),
            updateExecutionCapability: UpdateExecutionCapability(
                manager: .pipx,
                packageIdentifier: "aider-chat"
            ),
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        AIToolDefinition(
            id: "aiden",
            displayName: "Aiden",
            dataRootRelativePaths: [".aiden"],
            pluginRoots: [AIToolRootDescriptor(".aiden/plugins")],
            configRelativePaths: [".aiden"],
            cliProbeID: "aiden",
            packageDescriptors: [
                AIToolPackageDescriptor(
                    manager: .pnpm,
                    packageName: "@aiden-cli/core",
                    metadataRelativePaths: [".local/share/pnpm/global/5/node_modules/@aiden-cli/core/package.json"]
                )
            ],
            updateCapability: UpdateCapability(
                providerID: "npm",
                providerKind: .npmRegistry,
                packageIdentifier: "@aiden-cli/core"
            ),
            updateExecutionCapability: UpdateExecutionCapability(
                manager: .pnpm,
                packageIdentifier: "@aiden-cli/core"
            ),
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        AIToolDefinition(
            id: "copilot",
            displayName: "GitHub Copilot",
            applicationBundleIdentifiers: [],
            dataRootRelativePaths: [".config/github-copilot"],
            configRelativePaths: [".config/github-copilot"],
            cliProbeID: "copilot",
            agentProfile: localAgent([.cli], symbol: "terminal")
        ),
        // Continue / Cline / Roo are VS Code extensions, not standalone Agents:
        // they ship no independent application bundle and no controlled agent
        // executable. They surface only as VS Code host plugin/asset evidence
        // (see the `vscode` definition's `hostEvidenceRelativePaths`) and keep a
        // data/config footprint here WITHOUT an `agentProfile`, so they never
        // appear as standalone AI Agents.
        AIToolDefinition(
            id: "continue",
            displayName: "Continue",
            dataRootRelativePaths: [".continue"],
            configRelativePaths: [".continue"]
        ),
        AIToolDefinition(
            id: "cline",
            displayName: "Cline",
            dataRootRelativePaths: [".cline"],
            configRelativePaths: [".cline"]
        ),
        AIToolDefinition(
            id: "roo",
            displayName: "Roo Code",
            dataRootRelativePaths: [".roo"],
            configRelativePaths: [".roo"]
        ),
        AIToolDefinition(
            id: "ollama",
            displayName: "Ollama",
            applicationBundleIdentifiers: ["com.electron.ollama"],
            dataRootRelativePaths: [".ollama"],
            configRelativePaths: [".ollama"],
            cliProbeID: "ollama",
            agentProfile: localAgent([.application, .cli], symbol: "shippingbox")
        ),
        AIToolDefinition(
            id: "lm-studio",
            displayName: "LM Studio",
            applicationBundleIdentifiers: ["ai.elementlabs.lmstudio"],
            dataRootRelativePaths: [".lmstudio", ".cache/lm-studio"],
            configRelativePaths: [".lmstudio"],
            agentProfile: localAgent([.application], symbol: "cpu")
        ),
        AIToolDefinition(
            id: "jan",
            displayName: "Jan",
            applicationBundleIdentifiers: ["jan.ai.app"],
            dataRootRelativePaths: [".jan"],
            configRelativePaths: [".jan"],
            agentProfile: localAgent([.application], symbol: "cpu")
        ),
        // Real, bundle-verified AI applications confirmed on the target machine.
        // Each is keyed by a fixed bundle ID; none are matched by display name.
        AIToolDefinition(
            id: "aime",
            displayName: "Aime",
            applicationBundleIdentifiers: ["com.bytedance.aime.electron"],
            cliProbeID: "aime",
            agentProfile: localAgent([.application, .cli], symbol: "sparkles")
        ),
        AIToolDefinition(
            id: "mira",
            displayName: "Mira",
            applicationBundleIdentifiers: ["net.byteintl.mira"],
            cliProbeID: "mira",
            agentProfile: localAgent([.application, .cli], symbol: "sparkles")
        ),
        AIToolDefinition(
            id: "doubao",
            displayName: "Doubao",
            applicationBundleIdentifiers: ["com.bot.pc.doubao"],
            agentProfile: localAgent([.application], symbol: "bubble.left.and.bubble.right")
        ),
        AIToolDefinition(
            id: "cici",
            displayName: "Cici",
            applicationBundleIdentifiers: ["com.bot.pc.cici"],
            agentProfile: localAgent([.application], symbol: "bubble.left.and.bubble.right")
        ),
        AIToolDefinition(
            id: "m365-copilot",
            displayName: "Microsoft 365 Copilot",
            applicationBundleIdentifiers: ["com.microsoft.m365copilot.shim"],
            agentProfile: localAgent([.application], symbol: "square.grid.2x2")
        ),
        // CLI-only tools confirmed on the target machine. Each resolves through a
        // fixed, code-owned probe template (FNM node-versions, uv tool root,
        // Homebrew, or an exact home-relative install path); none is matched by
        // display name and none ships an AI application bundle.
        //
        // Warp was removed as an AI application: per the user's ruling it is a
        // terminal, not an AI Agent, so it must not appear under AI Agents.
        AIToolDefinition(
            id: "merlin-cli",
            displayName: "Merlin CLI",
            cliProbeID: "merlin-cli"
        ),
        AIToolDefinition(
            id: "one-cli",
            displayName: "One CLI",
            cliProbeID: "one"
        ),
        AIToolDefinition(
            id: "bytedcli",
            displayName: "Bytedcli",
            cliProbeID: "bytedcli"
        ),
        AIToolDefinition(
            id: "opencli",
            displayName: "OpenCLI",
            cliProbeID: "opencli"
        ),
        AIToolDefinition(
            id: "botmux",
            displayName: "botmux",
            cliProbeID: "botmux"
        ),
        // Traex is a Remote (cloud) AI Agent per the user's ruling. It is
        // detected through its fixed local client evidence, never treated as a
        // supporting CLI tool, and never appears in CLI Tools.
        AIToolDefinition(
            id: "traex",
            displayName: "Traex",
            cliProbeID: "traex",
            agentProfile: remoteAgent([.cloud, .cli], symbol: "cloud")
        ),
        AIToolDefinition(
            id: "lark-cli",
            displayName: "Lark CLI",
            cliProbeID: "lark-cli"
        )
    ]
}
