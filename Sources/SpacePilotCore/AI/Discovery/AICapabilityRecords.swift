import Foundation

// MARK: - MCP servers

/// How an MCP server is reached. Read from fixed config keys; never inferred
/// from the command string.
public enum MCPTransport: String, Codable, Hashable, Sendable {
    case stdio
    case http
    case sse
    /// The config did not state a transport and none can be established without
    /// guessing. Surfaced honestly rather than defaulting to `stdio`.
    case unknown
}

/// One MCP server declared in an Agent's configuration file.
///
/// This is discovery evidence, not a live probe: it records that an Agent's
/// config *declares* the server, which is what the Developer & AI page reports.
/// The server is never launched, and the `command` string is stored purely as
/// display evidence — it is never parsed for meaning or executed.
public struct MCPServerRecord: Identifiable, Codable, Hashable, Sendable {
    /// Deterministic: owner + name, so re-scanning an unchanged config yields
    /// the same id (no snapshot churn).
    public let id: String
    /// The server name exactly as written in the config.
    public let name: String
    /// The definition ID of the Agent whose config declares this server.
    public let ownerDefinitionID: String
    /// The config file this was read from, shown as evidence.
    public let sourceURL: URL
    public let transport: MCPTransport
    /// The declared command, kept verbatim for display only.
    public let command: String?
    /// Whether the config explicitly disables this server. `enabled = false`
    /// entries are still listed — a disabled server is a real thing the user
    /// installed and may want to clean up — but are labelled as disabled rather
    /// than silently hidden.
    public let isEnabled: Bool

    public init(
        name: String,
        ownerDefinitionID: String,
        sourceURL: URL,
        transport: MCPTransport,
        command: String?,
        isEnabled: Bool
    ) {
        self.id = "mcp:\(ownerDefinitionID):\(name)"
        self.name = name
        self.ownerDefinitionID = ownerDefinitionID
        self.sourceURL = sourceURL
        self.transport = transport
        self.command = command
        self.isEnabled = isEnabled
    }
}

// MARK: - Hooks

/// One hook event declared in an Agent's configuration, together with how many
/// handlers are attached to it.
///
/// Hooks are grouped per event rather than listed per handler because the user
/// question this answers is "what is intercepting this Agent, and at which
/// points" — a per-handler list would be longer without being more informative.
public struct HookRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    /// The event name exactly as written in config (`SessionStart`,
    /// `sessionStart`, ...). Case is preserved because it differs per Agent and
    /// normalising it would misrepresent the file.
    public let event: String
    public let ownerDefinitionID: String
    public let sourceURL: URL
    /// Number of handlers attached to this event.
    public let handlerCount: Int
    /// Distinct providers inferred *only* from unambiguous absolute paths inside
    /// handler commands (for example a `/Applications/Foo.app/...` prefix).
    /// Empty when nothing definite can be attributed — never guessed.
    public let providers: [String]

    public init(
        event: String,
        ownerDefinitionID: String,
        sourceURL: URL,
        handlerCount: Int,
        providers: [String] = []
    ) {
        self.id = "hook:\(ownerDefinitionID):\(event)"
        self.event = event
        self.ownerDefinitionID = ownerDefinitionID
        self.sourceURL = sourceURL
        self.handlerCount = handlerCount
        self.providers = providers
    }
}

// MARK: - Agent instruction files

/// A global instruction file that an Agent loads on every session (for example
/// `~/.codex/AGENTS.md`, `~/.claude/CLAUDE.md`).
///
/// Only user-global files are represented. Project-level instruction files are
/// deliberately out of scope: they live inside arbitrary project trees, and
/// enumerating them would mean walking the user's whole disk.
public struct AgentInstructionFile: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let ownerDefinitionID: String
    public let url: URL
    public let allocatedSize: Int64
    /// Line count, as a cheap proxy for "how much is being injected".
    public let lineCount: Int
    public let modifiedAt: Date?
    /// The document title: the first Markdown H1 (`# …`) if present, else nil.
    /// Parsed structurally, never guessed from the file name.
    public let title: String?
    /// Second-level section headings (`## …`), in document order, so the UI can
    /// summarise what the always-loaded instructions cover. Empty when none.
    public let sections: [String]

    public init(
        ownerDefinitionID: String,
        url: URL,
        allocatedSize: Int64,
        lineCount: Int,
        modifiedAt: Date?,
        title: String? = nil,
        sections: [String] = []
    ) {
        self.id = "instructions:\(ownerDefinitionID):\(url.canonicalizedDiscoveryPath)"
        self.ownerDefinitionID = ownerDefinitionID
        self.url = url
        self.allocatedSize = allocatedSize
        self.lineCount = lineCount
        self.modifiedAt = modifiedAt
        self.title = title
        self.sections = sections
    }

    private enum CodingKeys: String, CodingKey {
        case id, ownerDefinitionID, url, allocatedSize, lineCount, modifiedAt, title, sections
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        ownerDefinitionID = try container.decode(String.self, forKey: .ownerDefinitionID)
        url = try container.decode(URL.self, forKey: .url)
        allocatedSize = try container.decode(Int64.self, forKey: .allocatedSize)
        lineCount = try container.decode(Int.self, forKey: .lineCount)
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        // Older snapshots predate title/sections; default so history never breaks.
        title = try container.decodeIfPresent(String.self, forKey: .title)
        sections = try container.decodeIfPresent([String].self, forKey: .sections) ?? []
    }
}

// MARK: - Agent configuration profile

/// Read-only, non-secret facts read from an Agent's configuration file: which
/// model it is pinned to, its reasoning-effort setting, and *whether* a
/// credential is configured. This never captures or stores the credential value
/// itself — only its presence — matching the project's privacy rule that key
/// material is never read or displayed.
public struct AgentConfigProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let ownerDefinitionID: String
    public let sourceURL: URL
    /// The pinned model name, if the config declares one.
    public let model: String?
    /// The reasoning-effort setting (for example `high`), if declared.
    public let reasoningEffort: String?
    /// True when the config references a credential (an auth token key or a
    /// sibling auth file). The value is never read — only its existence.
    public let hasCredential: Bool

    public init(
        ownerDefinitionID: String,
        sourceURL: URL,
        model: String?,
        reasoningEffort: String?,
        hasCredential: Bool
    ) {
        self.id = "config:\(ownerDefinitionID):\(sourceURL.canonicalizedDiscoveryPath)"
        self.ownerDefinitionID = ownerDefinitionID
        self.sourceURL = sourceURL
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.hasCredential = hasCredential
    }

    /// Whether this profile carries any surfaced fact. An all-empty profile is
    /// not worth emitting.
    public var isEmpty: Bool {
        model == nil && reasoningEffort == nil && !hasCredential
    }
}

// MARK: - Other AI tools

/// What an "other AI tool" actually contributes. A tool is classified by the
/// role it plays for the Agents on this machine, because that is what makes it
/// worth listing: an app that manages Skills and an app that provides Hooks are
/// managed very differently even if both are `.app` bundles.
public enum OtherAIToolKind: String, Codable, Hashable, Sendable {
    /// Manages Skill/config files on behalf of Agents (for example CC Switch).
    case configurationManager
    /// Supplies hook handlers to one or more Agents.
    case hookProvider
    /// Registers itself as an MCP server.
    case mcpServer
    /// Ships plugins consumed by Agents.
    case pluginSource
    /// Installed via a package manager, without a more specific role.
    case packageInstalled
}

/// How the tool got onto the machine — the thing that determines how it is
/// updated or removed.
public enum OtherAIToolInstallMethod: String, Codable, Hashable, Sendable {
    case applicationBundle
    case npm
    case homebrew
    case pipx
    case mcpRegistration
    case unknown
}

/// An AI-adjacent tool that is not itself an Agent: it strengthens or manages
/// the Agents on this machine.
public struct OtherAIToolRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let kind: OtherAIToolKind
    public let installMethod: OtherAIToolInstallMethod
    /// Definition IDs of the Agents this tool demonstrably touches.
    public let affectedAgentIDs: [String]
    public let url: URL
    public let allocatedSize: Int64
    /// For hook providers, how many Agent events it attaches handlers to. Zero
    /// for tools whose role is not event interception.
    public let interceptedEventCount: Int

    public init(
        name: String,
        kind: OtherAIToolKind,
        installMethod: OtherAIToolInstallMethod,
        affectedAgentIDs: [String],
        url: URL,
        allocatedSize: Int64,
        interceptedEventCount: Int = 0
    ) {
        self.id = "other:\(name):\(url.canonicalizedDiscoveryPath)"
        self.name = name
        self.kind = kind
        self.installMethod = installMethod
        self.affectedAgentIDs = affectedAgentIDs
        self.url = url
        self.allocatedSize = allocatedSize
        self.interceptedEventCount = interceptedEventCount
    }
}
