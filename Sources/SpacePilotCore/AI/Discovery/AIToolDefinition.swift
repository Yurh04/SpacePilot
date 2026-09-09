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

public enum AIToolPackageManager: String, Codable, Hashable, Sendable {
    case brew
    case npm
    case pnpm
    case pipx
}

/// A fixed package receipt/metadata location that can establish an install fact.
/// These paths are code constants owned by the definition table; executable or
/// script fields found inside the metadata are never trusted or executed.
public struct AIToolPackageDescriptor: Hashable, Sendable {
    public let manager: AIToolPackageManager
    public let packageName: String
    public let metadataRelativePaths: [String]

    public init(
        manager: AIToolPackageManager,
        packageName: String,
        metadataRelativePaths: [String]
    ) {
        self.manager = manager
        self.packageName = packageName
        self.metadataRelativePaths = metadataRelativePaths
    }
}

public enum AIProjectAssetKind: String, Codable, Hashable, Sendable {
    case skills
    case plugin
    case pluginContainer
}

/// A fixed project-relative asset location. Project scanning only evaluates
/// these code constants beneath a user-approved project root.
public struct AIProjectAssetDescriptor: Hashable, Sendable {
    public let relativePath: String
    public let ownership: AIToolRootOwnership
    public let kind: AIProjectAssetKind

    public init(
        _ relativePath: String,
        ownership: AIToolRootOwnership = .tool,
        kind: AIProjectAssetKind
    ) {
        self.relativePath = relativePath
        self.ownership = ownership
        self.kind = kind
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

    /// For AI-enabled hosts (for example VS Code), fixed home-relative evidence
    /// paths that must exist before the host is considered AI-managed. This
    /// prevents a generic host app from being surfaced merely because its bundle
    /// is installed or its broad extensions directory exists.
    public let hostEvidenceRelativePaths: [String]

    /// The whitelist probe identifier used to look up a CLI version, if any.
    /// The probe itself owns the concrete candidate paths and version argument;
    /// definitions only reference an identifier so no executable path is ever
    /// sourced from data.
    public let cliProbeID: String?

    /// Fixed package receipt locations used only for read-only install facts.
    public let packageDescriptors: [AIToolPackageDescriptor]

    /// Fixed, code-owned update metadata provider. This is never sourced from
    /// PATH, package receipts, project config, plugin manifests, or scripts.
    public let updateCapability: UpdateCapability?

    /// Fixed, code-owned update EXECUTION capability. Separate from
    /// `updateCapability` (which only reads the latest version): this authorizes
    /// running a specific package manager to install the latest version. It is
    /// only ever set for tools whose manager + package identifier + install
    /// source are proven, and is never sourced from a manifest, receipt, config,
    /// or PATH. `nil` means the tool is checkable-only or handoff-only.
    public let updateExecutionCapability: UpdateExecutionCapability?

    /// Fixed project-relative Skills/Plugins roots, evaluated only inside a
    /// user-approved project root.
    public let projectAssetDescriptors: [AIProjectAssetDescriptor]

    /// Fixed, code-owned AI Agent classification. When non-nil, this definition
    /// is an AI Agent (surfaced under AI Agents, split into local/remote) rather
    /// than a supporting developer CLI. When nil, the definition is a supporting
    /// tool that only ever appears in CLI Tools. This is a definition constant
    /// and is never inferred from names or the presence of a local executable.
    public let agentProfile: AIAgentProfile?

    /// Opt-in: surface this tool purely from its managed directory when no
    /// application bundle and no runnable CLI executable are found. Some tools
    /// have no discoverable command (installed from source, or a command that
    /// lives outside the fixed probe locations) yet clearly exist on the machine
    /// because their config/data directory does. Only definitions that set this
    /// are ever surfaced from directory presence alone; every other tool keeps
    /// the strict "must have a real app or executable" rule, so a leftover
    /// dot-directory never fabricates a tool. Default `false`.
    public let surfacesFromDirectoryPresence: Bool

    public init(
        id: String,
        displayName: String,
        applicationBundleIdentifiers: [String] = [],
        dataRootRelativePaths: [String] = [],
        skillRoots: [AIToolRootDescriptor] = [],
        pluginRoots: [AIToolRootDescriptor] = [],
        configRelativePaths: [String] = [],
        hostEvidenceRelativePaths: [String] = [],
        cliProbeID: String? = nil,
        packageDescriptors: [AIToolPackageDescriptor] = [],
        updateCapability: UpdateCapability? = nil,
        updateExecutionCapability: UpdateExecutionCapability? = nil,
        projectAssetDescriptors: [AIProjectAssetDescriptor] = [],
        agentProfile: AIAgentProfile? = nil,
        surfacesFromDirectoryPresence: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.applicationBundleIdentifiers = applicationBundleIdentifiers
        self.dataRootRelativePaths = dataRootRelativePaths
        self.skillRoots = skillRoots
        self.pluginRoots = pluginRoots
        self.configRelativePaths = configRelativePaths
        self.hostEvidenceRelativePaths = hostEvidenceRelativePaths
        self.cliProbeID = cliProbeID
        self.packageDescriptors = packageDescriptors
        self.updateCapability = updateCapability
        self.updateExecutionCapability = updateExecutionCapability
        self.projectAssetDescriptors = projectAssetDescriptors
        self.agentProfile = agentProfile
        self.surfacesFromDirectoryPresence = surfacesFromDirectoryPresence
    }
}
