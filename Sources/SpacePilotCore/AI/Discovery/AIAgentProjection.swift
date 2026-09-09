import Foundation

/// A single AI Agent, unified from every piece of evidence that shares one
/// stable `definitionID`. An Agent is NOT an app-vs-CLI product: an application
/// bundle and a CLI executable for the same definition collapse into one Agent
/// with multiple `formFactors`.
///
/// This is a pure, `Sendable`, `Equatable` value with no SwiftUI, no file
/// system access, and no process spawning. It is produced by
/// `AIAgentProjection` from already-discovered `AIToolRecord`s.
public struct AIAgentEntry: Identifiable, Hashable, Sendable {
    /// The stable definition ID (for example `"codex"`), used as the identity.
    public let id: String
    public let displayName: String
    public let locality: AIAgentLocality
    /// The form factors actually evidenced on this machine (a subset of the
    /// definition's declared capabilities).
    public let formFactors: Set<AIAgentFormFactor>
    /// The resolved icon descriptor (installed app icon > bundled asset >
    /// symbol). The App layer turns this into an image.
    public let icon: AgentIconDescriptor
    public let applicationURL: URL?
    public let executableURL: URL?
    public let aliasExecutableURLs: [URL]
    public let detectedVersion: String?
    public let dataRoots: [URL]
    public let skillRoots: [URL]
    public let pluginRoots: [URL]
    public let configDirectories: [URL]
    public let coverageFailures: Set<AIToolCoverageFailure>

    public init(
        id: String,
        displayName: String,
        locality: AIAgentLocality,
        formFactors: Set<AIAgentFormFactor>,
        icon: AgentIconDescriptor,
        applicationURL: URL? = nil,
        executableURL: URL? = nil,
        aliasExecutableURLs: [URL] = [],
        detectedVersion: String? = nil,
        dataRoots: [URL] = [],
        skillRoots: [URL] = [],
        pluginRoots: [URL] = [],
        configDirectories: [URL] = [],
        coverageFailures: Set<AIToolCoverageFailure> = []
    ) {
        self.id = id
        self.displayName = displayName
        self.locality = locality
        self.formFactors = formFactors
        self.icon = icon
        self.applicationURL = applicationURL
        self.executableURL = executableURL
        self.aliasExecutableURLs = aliasExecutableURLs
        self.detectedVersion = detectedVersion
        self.dataRoots = dataRoots
        self.skillRoots = skillRoots
        self.pluginRoots = pluginRoots
        self.configDirectories = configDirectories
        self.coverageFailures = coverageFailures
    }
}

/// A pure, read-only projection that separates discovered AI Agents from
/// supporting CLI tools.
///
/// Rules enforced here:
/// - A definition is an Agent iff it carries an `AIAgentProfile` constant.
///   Nothing is classified by display name.
/// - Agent evidence sharing a `definitionID` merges into ONE `AIAgentEntry`.
/// - Local vs remote comes from the fixed profile `locality`, never from the
///   presence of a local executable.
/// - CLI Tools excludes every agent-capable definition, so an Agent CLI (Codex,
///   Aiden, Traex, …) never also appears under CLI Tools; the same executable /
///   alias is therefore never double-listed.
public struct AIAgentProjection: Sendable, Equatable {
    public let localAgents: [AIAgentEntry]
    public let remoteAgents: [AIAgentEntry]
    /// Records that remain genuine CLI tools (supporting developer CLIs that are
    /// not autonomous Agents). Deterministically ordered like before.
    public let cliTools: [AIToolRecord]

    public init(
        records: [AIToolRecord],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) {
        let definitionByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        // Preserve catalog order for deterministic agent ordering.
        let catalogIndex = Dictionary(
            uniqueKeysWithValues: definitions.enumerated().map { ($0.element.id, $0.offset) }
        )

        // Group all tool-owned records by their definition ID.
        var recordsByDefinition: [String: [AIToolRecord]] = [:]
        for record in records {
            guard case .tool(let definitionID) = record.owner else { continue }
            recordsByDefinition[definitionID, default: []].append(record)
        }

        var local: [AIAgentEntry] = []
        var remote: [AIAgentEntry] = []

        for (definitionID, group) in recordsByDefinition {
            guard let definition = definitionByID[definitionID],
                  let profile = definition.agentProfile else { continue }
            guard let entry = Self.makeEntry(
                definition: definition,
                profile: profile,
                records: group
            ) else { continue }
            switch profile.locality {
            case .local: local.append(entry)
            case .remote: remote.append(entry)
            }
        }

        let order: (AIAgentEntry, AIAgentEntry) -> Bool = { lhs, rhs in
            let l = catalogIndex[lhs.id] ?? Int.max
            let r = catalogIndex[rhs.id] ?? Int.max
            if l != r { return l < r }
            return lhs.id < rhs.id
        }
        self.localAgents = local.sorted(by: order)
        self.remoteAgents = remote.sorted(by: order)

        // CLI Tools: only `.cli` records whose owning definition is NOT an
        // Agent. Skills/plugins/applications stay out of this list. Ordering
        // mirrors the previous CLI ordering (display name, then id).
        let filteredCLIs = records.filter { record in
            guard record.kind == .cli else { return false }
            guard case .tool(let definitionID) = record.owner else { return true }
            return definitionByID[definitionID]?.agentProfile == nil
        }
        self.cliTools = filteredCLIs.sorted { lhs, rhs in
            let lhsName = lhs.displayName.lowercased()
            let rhsName = rhs.displayName.lowercased()
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.id < rhs.id
        }
    }

    public static let empty = AIAgentProjection(records: [])

    /// Builds one merged Agent entry from all records for a definition. Returns
    /// `nil` when the records carry no qualifying evidence for the Agent's
    /// declared form factors (so a config-only footprint never fabricates one).
    private static func makeEntry(
        definition: AIToolDefinition,
        profile: AIAgentProfile,
        records: [AIToolRecord]
    ) -> AIAgentEntry? {
        var merged = AIToolEvidence()
        var coverage: Set<AIToolCoverageFailure> = []
        var detectedFormFactors: Set<AIAgentFormFactor> = []

        for record in records {
            merged.merge(record.evidence)
            coverage.formUnion(record.coverageFailures)
            switch record.kind {
            case .application:
                detectedFormFactors.insert(.application)
            case .cli:
                // Desktop and CLI versions are independent; the CLI version is
                // the one used by the Agent's package update controls.
                if let version = record.evidence.detectedVersion {
                    merged.detectedVersion = version
                }
                // For a remote Agent, its local client executable is the cloud
                // form factor's local evidence; for a local Agent it is a CLI.
                detectedFormFactors.insert(profile.locality == .remote ? .cloud : .cli)
            case .skill, .plugin:
                break
            }
        }

        // An Agent must have at least one qualifying surface (app or executable
        // evidence). Skills/plugins alone (or a bare config directory) never
        // fabricate an Agent — UNLESS the definition explicitly opts into
        // directory-backed presence (a tool installed from source with no
        // discoverable command, for example DeepSeek Harness), in which case its
        // managed data/config directory is the qualifying evidence.
        let hasDirectoryPresence = definition.surfacesFromDirectoryPresence
            && (!merged.dataRoots.isEmpty || !merged.configDirectories.isEmpty)
        guard merged.applicationURL != nil || merged.executableURL != nil || hasDirectoryPresence else {
            return nil
        }

        // Constrain detected form factors to what the definition declares, so a
        // stray record can never advertise a capability the catalog did not.
        // Strict intersection: an empty intersection must NOT fall back to the
        // raw detected set, otherwise an application-only definition seen only
        // via a CLI executable would falsely advertise `.cli`. When the strict
        // intersection is empty the evidence does not match any declared form
        // factor, so reject the entry entirely rather than surface a formless
        // Agent (e.g. an application-only definition detected solely via a CLI
        // executable must not produce an Agent at all). A directory-presence
        // Agent has no app/CLI/cloud record, so it adopts its declared form
        // factors directly.
        var formFactors = detectedFormFactors.intersection(profile.formFactors)
        if formFactors.isEmpty, hasDirectoryPresence {
            formFactors = profile.formFactors
        }
        guard !formFactors.isEmpty else {
            return nil
        }

        var iconCandidates: [AgentIconDescriptor] = [.systemSymbol(name: profile.fallbackSymbolName)]
        if let assetName = profile.bundledAssetName {
            iconCandidates.append(.bundledAsset(name: assetName))
        }
        if let appURL = merged.applicationURL {
            iconCandidates.append(.installedApplication(appURL))
        }
        let icon = AgentIconDescriptor.resolve(from: iconCandidates)
            ?? .systemSymbol(name: profile.fallbackSymbolName)

        return AIAgentEntry(
            id: definition.id,
            displayName: definition.displayName,
            locality: profile.locality,
            formFactors: formFactors,
            icon: icon,
            applicationURL: merged.applicationURL,
            executableURL: merged.executableURL,
            aliasExecutableURLs: merged.aliasExecutableURLs,
            detectedVersion: merged.detectedVersion,
            dataRoots: merged.dataRoots,
            skillRoots: merged.skillRoots,
            pluginRoots: merged.pluginRoots,
            configDirectories: merged.configDirectories,
            coverageFailures: coverage
        )
    }
}
