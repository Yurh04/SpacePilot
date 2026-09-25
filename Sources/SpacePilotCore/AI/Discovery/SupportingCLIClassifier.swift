import Foundation

/// Splits the supporting-CLI records (the developer CLIs that are NOT AI Agents)
/// into two buckets using **runtime heuristics only** — nothing here reads the
/// definition catalog for an explicit role flag:
///
/// - **Command-line tools**: CLIs that give an AI Agent a `tool` capability,
///   invoked through a skill (for example `one-cli`, `bytedcli`, `lark-cli`).
///   These stay in the CLI Tools list.
/// - **Other AI tools**: standalone AI-adjacent tools that are not themselves an
///   Agent and are not a per-Agent tool provider (for example `botmux`, an
///   `openviking` memory server). These move out of CLI Tools and are surfaced
///   under "Other AI tools".
///
/// The classification is a pure, deterministic function of the record plus the
/// discovered MCP evidence, so it is fully testable and behaves identically on
/// any machine. It errs toward keeping a tool in CLI Tools: a tool is only
/// reclassified when a heuristic positively identifies it as standalone, so the
/// common case (a per-Agent tool CLI) is never mislabeled.
public enum SupportingCLIClassifier {
    public struct Result: Sendable, Equatable {
        /// Records that remain genuine per-Agent command-line tools.
        public let commandLineTools: [AIToolRecord]
        /// Records reclassified as standalone "other AI tools".
        public let otherTools: [AIToolRecord]

        public init(commandLineTools: [AIToolRecord], otherTools: [AIToolRecord]) {
            self.commandLineTools = commandLineTools
            self.otherTools = otherTools
        }
    }

    /// Case- and separator-insensitive capability tokens that mark a standalone
    /// AI-adjacent tool rather than an Agent tool provider. Matched as whole
    /// alphanumeric tokens (so `mux` matches `botmux`/`bot-mux` but not an
    /// unrelated word that merely contains the letters). Deliberately small and
    /// conservative to avoid sweeping in per-Agent tool CLIs.
    static let capabilityKeywords: Set<String> = [
        "memory", "mux", "viking", "recall", "knowledge"
    ]

    /// Definition IDs known to be standalone AI-adjacent tools rather than
    /// per-Agent tool providers, but whose names carry no capability keyword (for
    /// example `devspace`, an MCP-server workspace bridge; `csj-proxy`, an
    /// AI-request proxy). Kept here as a runtime signal — small, explicit and
    /// testable — rather than as a role flag on the definition table, so the
    /// catalog stays a plain data table. Matched on the owning definition ID.
    static let standaloneToolDefinitionIDs: Set<String> = [
        "devspace", "csj-proxy"
    ]

    /// Definition IDs whose tool *is* an MCP server by nature, independent of
    /// whether any Agent currently registers it (for example `devspace`, which
    /// exposes a local workspace through an MCP server). Used only to label the
    /// "other AI tools" row; a subset of `standaloneToolDefinitionIDs`.
    public static let mcpServerToolDefinitionIDs: Set<String> = [
        "devspace"
    ]

    /// Whether a reclassified record represents a tool that is inherently an MCP
    /// server, so callers can label it accurately without re-deriving the rule.
    public static func isInherentMCPServer(_ record: AIToolRecord) -> Bool {
        guard let id = definitionID(of: record) else { return false }
        return mcpServerToolDefinitionIDs.contains(id)
    }

    public static func classify(
        cliRecords: [AIToolRecord],
        mcpServers: [MCPServerRecord]
    ) -> Result {
        // Names/definition IDs registered as MCP servers, normalized for matching.
        let mcpNames = Set(mcpServers.map { normalize($0.name) })

        var commandLineTools: [AIToolRecord] = []
        var otherTools: [AIToolRecord] = []
        for record in cliRecords {
            if isOtherAITool(record, mcpNames: mcpNames) {
                otherTools.append(record)
            } else {
                commandLineTools.append(record)
            }
        }
        return Result(commandLineTools: commandLineTools, otherTools: otherTools)
    }

    /// True when a CLI record should be surfaced as a standalone "other AI tool".
    static func isOtherAITool(_ record: AIToolRecord, mcpNames: Set<String>) -> Bool {
        // Signal 1 — MCP evidence (strongest): the tool also registers itself as
        // an MCP server against some Agent, which a per-Agent tool CLI does not.
        let identityTokens = tokens(for: record)
        if identityTokens.contains(where: { mcpNames.contains($0) }) { return true }

        // Signal 2 — capability keyword in the name: a whole-token match against a
        // small, conservative vocabulary of standalone-tool capability words.
        let nameTokens = splitTokens(record.displayName).union(splitTokens(definitionID(of: record) ?? ""))
        if nameTokens.contains(where: { capabilityKeywords.contains($0) }) { return true }

        // Signal 3 — explicit standalone list: a small, code-owned set of
        // definition IDs known to be standalone AI-adjacent tools whose names
        // carry no capability keyword (for example `devspace`, `csj-proxy`).
        if let id = definitionID(of: record), standaloneToolDefinitionIDs.contains(id) {
            return true
        }

        return false
    }

    // MARK: - Helpers

    private static func definitionID(of record: AIToolRecord) -> String? {
        if case .tool(let id) = record.owner { return id }
        return nil
    }

    /// Normalized identity tokens for MCP matching: the display name and the
    /// definition ID, each collapsed to lowercase alphanumerics.
    private static func tokens(for record: AIToolRecord) -> Set<String> {
        var result: Set<String> = [normalize(record.displayName)]
        if let id = definitionID(of: record) { result.insert(normalize(id)) }
        return result
    }

    /// Collapses a string to its lowercase alphanumeric run, dropping separators
    /// so `Lark CLI`, `lark-cli`, and `larkcli` compare equal.
    static func normalize(_ raw: String) -> String {
        String(raw.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }

    /// Splits a name into lowercase alphanumeric tokens on any non-alphanumeric
    /// boundary, and additionally emits sub-tokens for concatenated words like
    /// `botmux` so a keyword (`mux`) embedded in a compound name is found.
    static func splitTokens(_ raw: String) -> Set<String> {
        let lowered = raw.lowercased()
        var tokens: Set<String> = []
        var current = ""
        for scalar in lowered.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.insert(current)
                current = ""
            }
        }
        if !current.isEmpty { tokens.insert(current) }
        // Emit any capability keyword that appears as a substring of a token, so a
        // compound like `botmux` yields `mux`. Bounded to the known vocabulary so
        // this never explodes into arbitrary substrings.
        for token in tokens {
            for keyword in capabilityKeywords where token.contains(keyword) {
                tokens.insert(keyword)
            }
        }
        return tokens
    }
}
