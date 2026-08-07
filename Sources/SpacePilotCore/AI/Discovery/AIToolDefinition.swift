import Foundation

/// Whether a discovered root belongs to a single tool or is shared across
/// agents (for example, a shared `~/.agents/skills` directory).
public enum AIToolRootOwnership: Hashable, Sendable {
    case tool
    case shared
}

/// A home-relative root to look for, tagged with ownership semantics so the
/// registry can attribute it to a single tool or collapse it into one shared
/// record across every tool that references the same canonical path.
public struct AIToolRootDescriptor: Hashable, Sendable {
    public let relativePath: String
    public let ownership: AIToolRootOwnership
    /// Overrides the display name for shared records, where the owning tool's
    /// name would be misleading.
    public let displayNameOverride: String?

    public init(
        _ relativePath: String,
        ownership: AIToolRootOwnership = .tool,
        displayNameOverride: String? = nil
    ) {
        self.relativePath = relativePath
        self.ownership = ownership
        self.displayNameOverride = displayNameOverride
    }
}

/// A pure, read-only description of a known AI tool. It carries no behavior:
/// it does not import SwiftUI, touch the file system, or spawn processes. All
/// discovery logic lives in `AIToolRegistry`; this type only says *what to look
/// for*, keeping the known-tool catalog fully decoupled from the engine.
public struct AIToolDefinition: Identifiable, Hashable, Sendable {
    /// A stable, human-authored identifier (for example, `"codex"`). Used both
    /// as `Identifiable.id` and as the owner token in generated record IDs, so
    /// it must never change once shipped.
    public let id: String
    public let displayName: String

    /// Candidate application bundle identifiers, if this tool ships a `.app`.
    public let applicationBundleIdentifiers: [String]

    /// Home-relative data roots (for example, `".codex"`).
    public let dataRootRelativePaths: [String]

    /// Skill roots, each tagged with tool/shared ownership.
    public let skillRoots: [AIToolRootDescriptor]

    /// Plugin roots, each tagged with tool/shared ownership.
    public let pluginRoots: [AIToolRootDescriptor]

    /// Home-relative config directories worth surfacing (read-only).
    public let configRelativePaths: [String]

    /// The whitelist probe identifier used to look up a CLI version, if any.
    /// The probe itself owns the concrete candidate paths and version argument;
    /// definitions only reference an identifier so no executable path is ever
    /// sourced from data.
    public let cliProbeID: String?

    public init(
        id: String,
        displayName: String,
        applicationBundleIdentifiers: [String] = [],
        dataRootRelativePaths: [String] = [],
        skillRoots: [AIToolRootDescriptor] = [],
        pluginRoots: [AIToolRootDescriptor] = [],
        configRelativePaths: [String] = [],
        cliProbeID: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.applicationBundleIdentifiers = applicationBundleIdentifiers
        self.dataRootRelativePaths = dataRootRelativePaths
        self.skillRoots = skillRoots
        self.pluginRoots = pluginRoots
        self.configRelativePaths = configRelativePaths
        self.cliProbeID = cliProbeID
    }
}
