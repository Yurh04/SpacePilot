import SpacePilotCore
import SwiftUI

/// Read-only MCP servers page.
///
/// Lists every MCP server declared in the discovered Agents' configuration
/// files. Servers the config explicitly disables are still listed, marked as
/// disabled: a disabled server is still installed, still occupies space, and is
/// still something the user may want to know about — hiding it would misreport
/// the machine. Double-click reveals the config file the row came from.
struct MCPServersView: View {
    let servers: [MCPServerRecord]
    let agents: [AIAgentEntry]
    let searchText: String
    @State private var selection: Set<String> = []

    private var filtered: [MCPServerRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return servers }
        return servers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || displayName(forAgent: $0.ownerDefinitionID).localizedCaseInsensitiveContains(query)
        }
    }

    /// Resolves an owner definition ID to the Agent's display name, falling back
    /// to the raw ID so an unmapped owner is still identifiable rather than blank.
    private func displayName(forAgent id: String) -> String {
        agents.first { $0.id == id }?.displayName ?? id
    }

    var body: some View {
        if servers.isEmpty {
            ContentUnavailableView(
                L10n.text(.aiMCPEmpty),
                systemImage: "arrow.left.arrow.right"
            )
        } else if filtered.isEmpty {
            ContentUnavailableView(
                L10n.text(.aiStateNoResults),
                systemImage: "magnifyingglass"
            )
        } else {
            Table(filtered, selection: $selection) {
                TableColumn(L10n.text(.name)) { server in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.name)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(server.sourceURL.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                TableColumn(L10n.text(.aiMCPUsedBy)) { server in
                    Text(displayName(forAgent: server.ownerDefinitionID))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .width(min: 90, ideal: 120, max: 170)
                TableColumn(L10n.text(.aiMCPTransport)) { server in
                    Text(server.transport == .unknown ? "—" : server.transport.rawValue)
                        .foregroundStyle(server.transport == .unknown ? .secondary : .primary)
                        .lineLimit(1)
                }
                .width(min: 64, ideal: 78, max: 96)
                TableColumn(L10n.text(.aiMCPState)) { server in
                    Text(server.isEnabled
                         ? L10n.text(.aiMCPEnabled)
                         : L10n.text(.aiMCPDisabled))
                        .foregroundStyle(server.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                }
                .width(min: 56, ideal: 70, max: 88)
            }
            .nativeTableDoubleClickReveal { row in
                guard filtered.indices.contains(row) else { return nil }
                return filtered[row].sourceURL
            }
        }
    }
}
