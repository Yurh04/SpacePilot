import Foundation

/// Derives the "other AI tools" list — tools that are not Agents themselves but
/// strengthen or manage the Agents on this machine.
///
/// Everything here comes from evidence discovery already proved: an app appears
/// as a hook provider only because its absolute path occurs in a hook command,
/// and as an MCP server only because an Agent's config registers it. Nothing is
/// inferred from a name, and no tool is invented to fill the list.
///
/// The record carries *counts* rather than a prose sentence, so the view owns
/// wording and localisation while this layer stays pure and testable.
public enum OtherAIToolProjection {
    public static func tools(
        hooks: [HookRecord],
        mcpServers: [MCPServerRecord],
        reclassifiedCLIs: [AIToolRecord] = []
    ) -> [OtherAIToolRecord] {
        var tools: [OtherAIToolRecord] = []

        // Hook providers, grouped by provider: one app that hooks four Agents
        // should be one row that says "4 Agents", not four separate rows.
        var agentsByProvider: [String: Set<String>] = [:]
        var eventsByProvider: [String: Int] = [:]
        for hook in hooks {
            for provider in hook.providers {
                agentsByProvider[provider, default: []].insert(hook.ownerDefinitionID)
                eventsByProvider[provider, default: 0] += 1
            }
        }
        for provider in agentsByProvider.keys.sorted() {
            let agents = (agentsByProvider[provider] ?? []).sorted()
            tools.append(OtherAIToolRecord(
                name: provider,
                kind: .hookProvider,
                installMethod: .applicationBundle,
                affectedAgentIDs: agents,
                url: URL(fileURLWithPath: "/Applications/\(provider).app"),
                allocatedSize: 0,
                interceptedEventCount: eventsByProvider[provider] ?? 0
            ))
        }

        // MCP servers registered against at least one Agent. A name that is also
        // a hook provider is not repeated: the hook role is more specific and
        // already conveys the relationship.
        var agentsByServer: [String: Set<String>] = [:]
        for server in mcpServers {
            agentsByServer[server.name, default: []].insert(server.ownerDefinitionID)
        }
        for name in agentsByServer.keys.sorted() where agentsByProvider[name] == nil {
            let source = mcpServers.first { $0.name == name }
            tools.append(OtherAIToolRecord(
                name: name,
                kind: .mcpServer,
                installMethod: .mcpRegistration,
                affectedAgentIDs: (agentsByServer[name] ?? []).sorted(),
                url: source?.sourceURL ?? URL(fileURLWithPath: "/"),
                allocatedSize: 0,
                interceptedEventCount: 0
            ))
        }

        // Supporting CLIs reclassified as standalone AI tools (for example a
        // `botmux`, or an `openviking` memory server). They arrive already
        // filtered by SupportingCLIClassifier; here they become rows with an
        // install method inferred from where the executable lives. A name already
        // represented as a hook provider or MCP server above is not duplicated.
        let existingNames = Set(tools.map { $0.name.lowercased() })
        for record in reclassifiedCLIs.sorted(by: { $0.displayName.lowercased() < $1.displayName.lowercased() }) {
            guard !existingNames.contains(record.displayName.lowercased()) else { continue }
            let url = record.evidence.executableURL ?? URL(fileURLWithPath: "/")
            tools.append(OtherAIToolRecord(
                name: record.displayName,
                kind: .packageInstalled,
                installMethod: installMethod(for: url),
                affectedAgentIDs: [],
                url: url,
                allocatedSize: 0,
                interceptedEventCount: 0
            ))
        }

        return tools
    }

    /// Infers how a reclassified CLI got onto the machine from its executable
    /// path. Delegates to the shared `AIInstallSource` classifier so the CLI list
    /// and this list agree. Purely for display; nothing is executed.
    private static func installMethod(for url: URL) -> OtherAIToolInstallMethod {
        AIInstallSource.classify(executableURL: url).otherToolInstallMethod
    }
}
