import SpacePilotCore
import SwiftUI

/// One row in the Developer & AI sidebar.
///
/// The sidebar is a flat list of three kinds of rows rather than a nested tree:
/// Overview, then one row per discovered AI, then one row per capability type.
/// Agents sit at the same level as capabilities because both answer "what is on
/// this machine" — an Agent is not a container you must open to reach its
/// Skills, it is one lens on them, and the capability rows are the other.
enum DeveloperAISidebarRow: Hashable, Identifiable {
    case overview
    /// A discovered AI, keyed by its stable definition ID.
    case agent(id: String)
    case skills
    case mcp
    case plugins
    case cli
    case otherTools

    var id: String {
        switch self {
        case .overview: "overview"
        case .agent(let id): "agent:\(id)"
        case .skills: "skills"
        case .mcp: "mcp"
        case .plugins: "plugins"
        case .cli: "cli"
        case .otherTools: "other"
        }
    }

    /// The capability rows, in the order they appear beneath the Agent rows.
    static let capabilityRows: [DeveloperAISidebarRow] = [
        .skills, .mcp, .plugins, .cli, .otherTools
    ]

    /// SF Symbol for the non-Agent rows. Agent rows use the real application
    /// icon instead, so they are not covered here.
    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .skills: "sparkles"
        case .mcp: "arrow.left.arrow.right"
        case .plugins: "puzzlepiece.extension"
        case .cli: "terminal"
        case .otherTools: "wrench.and.screwdriver"
        case .agent: "brain.head.profile"
        }
    }

    var title: String {
        switch self {
        case .overview: L10n.overview()
        case .skills: L10n.skills()
        case .mcp: L10n.text(.aiSectionMCP)
        case .plugins: L10n.plugins()
        case .cli: L10n.text(.aiSectionCLI)
        case .otherTools: L10n.text(.aiSectionOtherTools)
        case .agent: ""
        }
    }
}
