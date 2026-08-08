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

    public static let all: [AIToolDefinition] = [
        AIToolDefinition(
            id: "codex",
            displayName: "Codex",
            applicationBundleIdentifiers: ["com.openai.codex"],
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
            projectAssetDescriptors: [
                AIProjectAssetDescriptor(".codex/skills", kind: .skills),
                AIProjectAssetDescriptor(".codex/plugins", kind: .pluginContainer),
                sharedProjectSkills
            ]
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
            ]
        ),
        AIToolDefinition(
            id: "chatgpt",
            displayName: "ChatGPT",
            applicationBundleIdentifiers: ["com.openai.chat"],
            dataRootRelativePaths: [],
            configRelativePaths: []
        ),
        AIToolDefinition(
            id: "cursor",
            displayName: "Cursor",
            applicationBundleIdentifiers: ["com.todesktop.230313mzl4w4u92"],
            dataRootRelativePaths: [".cursor"],
            configRelativePaths: [".cursor"],
            cliProbeID: "cursor"
        ),
        AIToolDefinition(
            id: "trae-cn",
            displayName: "Trae CN",
            applicationBundleIdentifiers: ["cn.trae.app"],
            dataRootRelativePaths: [".trae"],
            configRelativePaths: [".trae"],
            cliProbeID: "trae"
        ),
        AIToolDefinition(
            id: "trae-solo-cn",
            displayName: "TRAE SOLO CN",
            applicationBundleIdentifiers: ["cn.trae.solo.app"],
            dataRootRelativePaths: [".trae-solo", ".traework"],
            configRelativePaths: [".trae-solo", ".traework"],
            cliProbeID: "traework"
        ),
        AIToolDefinition(
            id: "antigravity",
            displayName: "Antigravity",
            applicationBundleIdentifiers: ["com.google.antigravity"],
            dataRootRelativePaths: [".antigravity"],
            configRelativePaths: [".antigravity"],
            cliProbeID: "antigravity"
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
            ]
        ),
        AIToolDefinition(
            id: "windsurf",
            displayName: "Windsurf",
            applicationBundleIdentifiers: ["com.exafunction.windsurf"],
            dataRootRelativePaths: [".windsurf", ".codeium"],
            configRelativePaths: [".windsurf"],
            cliProbeID: "windsurf"
        ),
        AIToolDefinition(
            id: "gemini-cli",
            displayName: "Gemini CLI",
            dataRootRelativePaths: [".gemini"],
            configRelativePaths: [".gemini"],
            cliProbeID: "gemini"
        ),
        AIToolDefinition(
            id: "opencode",
            displayName: "OpenCode",
            dataRootRelativePaths: [".opencode", ".config/opencode"],
            configRelativePaths: [".config/opencode"],
            cliProbeID: "opencode"
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
            ]
        ),
        AIToolDefinition(
            id: "aiden",
            displayName: "Aiden CLI",
            dataRootRelativePaths: [".aiden"],
            configRelativePaths: [".aiden"],
            cliProbeID: "aiden",
            packageDescriptors: [
                AIToolPackageDescriptor(
                    manager: .pnpm,
                    packageName: "@aiden-cli/core",
                    metadataRelativePaths: [".local/share/pnpm/global/5/node_modules/@aiden-cli/core/package.json"]
                )
            ]
        ),
        AIToolDefinition(
            id: "copilot",
            displayName: "GitHub Copilot",
            applicationBundleIdentifiers: [],
            dataRootRelativePaths: [".config/github-copilot"],
            configRelativePaths: [".config/github-copilot"],
            cliProbeID: "copilot"
        ),
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
            cliProbeID: "ollama"
        ),
        AIToolDefinition(
            id: "lm-studio",
            displayName: "LM Studio",
            applicationBundleIdentifiers: ["ai.elementlabs.lmstudio"],
            dataRootRelativePaths: [".lmstudio", ".cache/lm-studio"],
            configRelativePaths: [".lmstudio"]
        ),
        AIToolDefinition(
            id: "jan",
            displayName: "Jan",
            applicationBundleIdentifiers: ["jan.ai.app"],
            dataRootRelativePaths: [".jan"],
            configRelativePaths: [".jan"]
        )
    ]
}
