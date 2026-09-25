import Foundation

/// Discovers the AI capabilities that live in *configuration files* rather than
/// on disk as directories: MCP servers, hooks, and global instruction files.
///
/// Design constraints, all deliberate:
///
/// - **Read-only.** Files are parsed; nothing is written, launched or executed.
///   A declared MCP `command` is captured as a display string only.
/// - **Fixed locations.** Only the paths named in `KnownAgentConfigLocations`
///   are read. Nothing is discovered by walking the disk, so an unrelated file
///   can never pull the scanner somewhere unexpected.
/// - **Honest partial results.** A malformed or unreadable file yields no
///   records for that file and is reported in `failures`, rather than being
///   silently swallowed or aborting the whole scan.
public struct AICapabilityScanner: Sendable {
    public init() {}

    /// Matches the convention used by the other Core scanners: reach for the
    /// shared `FileManager` at the point of use rather than storing it, which
    /// keeps the scanner `Sendable` under strict concurrency.
    private var fileManager: FileManager { .default }

    /// Everything one scan pass found, plus the files it could not read.
    public struct Result: Sendable, Equatable {
        public var mcpServers: [MCPServerRecord] = []
        public var hooks: [HookRecord] = []
        public var instructionFiles: [AgentInstructionFile] = []
        /// Per-Agent config facts (model / reasoning effort / credential presence).
        public var configProfiles: [AgentConfigProfile] = []
        /// Paths that exist but could not be parsed, with the reason. Surfaced so
        /// the UI can say "we could not read this" instead of "there is nothing".
        public var failures: [String: AIToolCoverageFailure] = [:]

        public init() {}
    }

    public func scan(homeDirectory: URL) -> Result {
        var result = Result()
        for location in KnownAgentConfigLocations.all {
            let url = homeDirectory.appending(path: location.relativePath)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            switch location.format {
            case .codexTOML:
                scanCodexTOML(at: url, agentID: location.agentID, into: &result)
            case .claudeSettingsJSON:
                scanJSON(at: url, agentID: location.agentID, hooksKey: "hooks",
                         mcpKey: "mcpServers", extractConfigProfile: true, into: &result)
            case .claudeRootJSON:
                scanJSON(at: url, agentID: location.agentID, hooksKey: nil,
                         mcpKey: "mcpServers", extractConfigProfile: false, into: &result)
            case .cursorHooksJSON:
                scanJSON(at: url, agentID: location.agentID, hooksKey: "hooks",
                         mcpKey: nil, extractConfigProfile: false, into: &result)
            case .instructionMarkdown:
                scanInstructions(at: url, agentID: location.agentID, into: &result)
            }
        }
        return result
    }

    // MARK: - Codex TOML

    /// Reads `[mcp_servers.NAME]` tables out of Codex's `config.toml`.
    ///
    /// This is a *targeted* reader, not a TOML implementation: it recognises
    /// table headers and simple `key = "value"` / `key = false` lines, which is
    /// all the MCP block uses. Anything it does not recognise is skipped rather
    /// than guessed at, so an exotic TOML construct elsewhere in the file cannot
    /// produce a wrong record — at worst it produces no record.
    private func scanCodexTOML(at url: URL, agentID: String, into result: inout Result) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            result.failures[url.path] = .permissionDenied
            return
        }

        var servers: [String: (transport: String?, command: String?, enabled: Bool)] = [:]
        var order: [String] = []
        var currentServer: String?
        // Top-level (pre-table) scalar keys, for the config profile. Only keys
        // seen before any `[table]` header count as top-level.
        var inTopLevel = true
        var model: String?
        var reasoningEffort: String?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inTopLevel = false
                // A new table header always ends the previous server's scope.
                currentServer = nil
                let header = line.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                let prefix = "mcp_servers."
                guard header.hasPrefix(prefix) else { continue }
                let remainder = String(header.dropFirst(prefix.count))
                // `[mcp_servers.foo.env]` is a sub-table of `foo`, not a server.
                guard !remainder.contains(".") else { continue }
                let name = remainder.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                guard !name.isEmpty else { continue }
                if servers[name] == nil {
                    servers[name] = (nil, nil, true)
                    order.append(name)
                }
                currentServer = name
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if let server = currentServer {
                switch key {
                case "type": servers[server]?.transport = value
                case "command": servers[server]?.command = value
                case "enabled": servers[server]?.enabled = (value != "false")
                default: break
                }
            } else if inTopLevel {
                // Codex pins the model with `model = "…"` and reasoning depth with
                // `model_reasoning_effort = "…"`. Only these two fixed keys are read.
                switch key {
                case "model" where !value.isEmpty: model = value
                case "model_reasoning_effort" where !value.isEmpty: reasoningEffort = value
                default: break
                }
            }
        }

        // Credential presence: Codex stores its token in a sibling `auth.json`.
        // Only existence is checked — the file is never opened or read.
        let authURL = url.deletingLastPathComponent().appending(path: "auth.json")
        let hasCredential = fileManager.fileExists(atPath: authURL.path)
        let profile = AgentConfigProfile(
            ownerDefinitionID: agentID,
            sourceURL: url,
            model: model,
            reasoningEffort: reasoningEffort,
            hasCredential: hasCredential
        )
        if !profile.isEmpty { result.configProfiles.append(profile) }

        for name in order {
            guard let entry = servers[name] else { continue }
            result.mcpServers.append(MCPServerRecord(
                name: name,
                ownerDefinitionID: agentID,
                sourceURL: url,
                transport: Self.transport(from: entry.transport),
                command: entry.command,
                isEnabled: entry.enabled
            ))
        }
    }

    // MARK: - JSON configs

    private func scanJSON(
        at url: URL,
        agentID: String,
        hooksKey: String?,
        mcpKey: String?,
        extractConfigProfile: Bool,
        into result: inout Result
    ) {
        guard let data = try? Data(contentsOf: url) else {
            result.failures[url.path] = .permissionDenied
            return
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            result.failures[url.path] = .invalidOutput
            return
        }

        if extractConfigProfile {
            // Model: a plain top-level `model` string. Credential presence: an
            // `env` auth-token key, an `apiKeyHelper`, or a sibling auth file —
            // the value is never read, only its existence noted.
            let model = ((root["model"] ?? root["defaultModel"]) as? String).flatMap { $0.isEmpty ? nil : $0 }
            let effort = (root["reasoning_effort"] ?? root["defaultThinkingLevel"]) as? String
            let env = root["env"] as? [String: Any] ?? [:]
            let hasEnvToken = env.keys.contains { key in
                let k = key.uppercased()
                return k.contains("AUTH_TOKEN") || k.contains("API_KEY")
            }
            let hasHelper = (root["apiKeyHelper"] as? String).map { !$0.isEmpty } ?? false
            let hasSibling = [".credentials.json", "auth.json"].contains {
                fileManager.fileExists(atPath: url.deletingLastPathComponent().appending(path: $0).path)
            }
            let profile = AgentConfigProfile(
                ownerDefinitionID: agentID,
                sourceURL: url,
                model: model,
                reasoningEffort: effort,
                hasCredential: hasEnvToken || hasHelper || hasSibling
            )
            if !profile.isEmpty { result.configProfiles.append(profile) }
        }

        if let mcpKey, let servers = root[mcpKey] as? [String: Any] {
            for name in servers.keys.sorted() {
                let body = servers[name] as? [String: Any] ?? [:]
                result.mcpServers.append(MCPServerRecord(
                    name: name,
                    ownerDefinitionID: agentID,
                    sourceURL: url,
                    transport: Self.transport(from: body["type"] as? String),
                    command: body["command"] as? String,
                    isEnabled: (body["enabled"] as? Bool) ?? true
                ))
            }
        }

        if let hooksKey, let hooks = root[hooksKey] as? [String: Any] {
            for event in hooks.keys.sorted() {
                let handlers = Self.handlers(in: hooks[event])
                result.hooks.append(HookRecord(
                    event: event,
                    ownerDefinitionID: agentID,
                    sourceURL: url,
                    handlerCount: handlers.count,
                    providers: Self.providers(in: handlers)
                ))
            }
        }
    }

    /// Counts handlers for one event across the two shapes seen in real config:
    /// a flat list of handlers, or a list of matcher groups each wrapping its own
    /// `hooks` array.
    private static func handlers(in value: Any?) -> [[String: Any]] {
        guard let entries = value as? [[String: Any]] else { return [] }
        var flattened: [[String: Any]] = []
        for entry in entries {
            if let nested = entry["hooks"] as? [[String: Any]] {
                flattened.append(contentsOf: nested)
            } else {
                flattened.append(entry)
            }
        }
        return flattened
    }

    /// Attributes handlers to a provider **only** when the command contains an
    /// unambiguous `/Applications/<Name>.app` path. Any other command yields no
    /// attribution: a wrong provider name is worse than none.
    private static func providers(in handlers: [[String: Any]]) -> [String] {
        var names: [String] = []
        for handler in handlers {
            guard let command = handler["command"] as? String else { continue }
            guard let range = command.range(of: "/Applications/") else { continue }
            let tail = command[range.upperBound...]
            guard let appRange = tail.range(of: ".app") else { continue }
            let name = String(tail[tail.startIndex..<appRange.lowerBound])
            guard !name.isEmpty, !name.contains("/") else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names.sorted()
    }

    // MARK: - Instruction files

    private func scanInstructions(at url: URL, agentID: String, into result: inout Result) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            result.failures[url.path] = .permissionDenied
            return
        }
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let outline = Self.markdownOutline(lines: lines)
        result.instructionFiles.append(AgentInstructionFile(
            ownerDefinitionID: agentID,
            url: url,
            allocatedSize: size,
            lineCount: lines.count,
            modifiedAt: attributes?[.modificationDate] as? Date,
            title: outline.title,
            sections: outline.sections
        ))
    }

    /// Extracts the first H1 (`# …`) as the title and all H2 (`## …`) headings as
    /// sections, in document order. This is a targeted heading reader, not a
    /// Markdown implementation: it recognises only ATX headings at the start of a
    /// line, ignores fenced code blocks so a `#` inside code is never mistaken for
    /// a heading, and caps how many sections it keeps so a pathological file
    /// cannot blow up memory. Content is never stored — only heading text.
    static func markdownOutline(lines: [Substring]) -> (title: String?, sections: [String]) {
        var title: String?
        var sections: [String] = []
        var insideFence = false
        let maxSections = 40
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }
            if title == nil, line.hasPrefix("# "), !line.hasPrefix("## ") {
                title = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("## "), !line.hasPrefix("### ") {
                let heading = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty, sections.count < maxSections {
                    sections.append(heading)
                }
            }
        }
        return (title, sections)
    }

    private static func transport(from raw: String?) -> MCPTransport {
        guard let raw else { return .unknown }
        return MCPTransport(rawValue: raw.lowercased()) ?? .unknown
    }
}

/// The fixed set of configuration files the scanner is allowed to read.
///
/// Keeping these as code constants (rather than deriving them from discovered
/// records or user data) is what bounds the scanner: it can only ever read this
/// list, so its blast radius is reviewable at a glance.
public enum KnownAgentConfigLocations {
    public enum Format: Sendable {
        case codexTOML
        case claudeSettingsJSON
        case claudeRootJSON
        case cursorHooksJSON
        case instructionMarkdown
    }

    public struct Location: Sendable {
        public let agentID: String
        public let relativePath: String
        public let format: Format
    }

    public static let all: [Location] = [
        Location(agentID: "codex", relativePath: ".codex/config.toml", format: .codexTOML),
        Location(agentID: "codex", relativePath: ".codex/hooks.json", format: .cursorHooksJSON),
        Location(agentID: "codex", relativePath: ".codex/AGENTS.md", format: .instructionMarkdown),
        Location(agentID: "claude", relativePath: ".claude/settings.json", format: .claudeSettingsJSON),
        Location(agentID: "claude", relativePath: ".claude.json", format: .claudeRootJSON),
        Location(agentID: "claude", relativePath: ".claude/CLAUDE.md", format: .instructionMarkdown),
        Location(agentID: "cursor", relativePath: ".cursor/hooks.json", format: .cursorHooksJSON),
        Location(agentID: "cursor", relativePath: ".cursor/mcp.json", format: .claudeRootJSON),
        Location(agentID: "gemini-cli", relativePath: ".gemini/settings.json", format: .claudeSettingsJSON),
        Location(agentID: "gemini-cli", relativePath: ".gemini/GEMINI.md", format: .instructionMarkdown),
        Location(agentID: "opencode", relativePath: ".config/opencode/opencode.json", format: .claudeSettingsJSON),
        Location(agentID: "relay", relativePath: ".relay/settings.json", format: .claudeSettingsJSON),
        Location(agentID: "relay", relativePath: ".relay/CLAUDE.md", format: .instructionMarkdown),
        Location(agentID: "pi", relativePath: ".pi/agent/settings.json", format: .claudeSettingsJSON),
        Location(agentID: "pi", relativePath: ".pi/agent/AGENTS.md", format: .instructionMarkdown),
        Location(agentID: "aime", relativePath: ".aime/config.json", format: .claudeSettingsJSON),
        Location(agentID: "mira", relativePath: ".mira/config.json", format: .claudeSettingsJSON),
        Location(agentID: "copilot", relativePath: ".copilot/config.json", format: .claudeSettingsJSON),
        Location(agentID: "copilot", relativePath: ".copilot/mcp-config.json", format: .claudeRootJSON)
    ]
}
