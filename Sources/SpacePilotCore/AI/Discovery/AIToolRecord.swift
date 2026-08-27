import Foundation

/// The kind of AI-related asset discovered on disk.
public enum AIToolKind: String, Codable, Hashable, Sendable {
    case application
    case cli
    case skill
    case plugin
}

/// Who owns a discovered record: a specific tool definition, or a location
/// shared across agents (for example, a shared Skills directory).
public enum AIToolOwner: Codable, Hashable, Sendable {
    /// Owned by a single tool, identified by its stable definition ID.
    case tool(definitionID: String)
    /// Not attributable to a single tool (for example, shared Skills).
    case shared
}

/// Read-only evidence explaining why a record was discovered. Every field is
/// optional so that partial evidence (for example, a CLI found by path but with
/// an unreadable version) is still representable without loss.
public struct AIToolEvidence: Codable, Hashable, Sendable {
    public var bundleIdentifier: String?
    public var applicationURL: URL?
    public var executableURL: URL?
    /// Fixed alias executables (for example `trae-cli` / `trae-agent`) that
    /// canonically resolve to the same `executableURL`. Kept as read-only
    /// evidence so the UI shows one CLI with its known aliases rather than
    /// duplicate rows; the aliases are never executed on their own.
    public var aliasExecutableURLs: [URL]
    public var detectedVersion: String?
    public var dataRoots: [URL]
    public var skillRoots: [URL]
    public var pluginRoots: [URL]
    public var configDirectories: [URL]

    public init(
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil,
        executableURL: URL? = nil,
        aliasExecutableURLs: [URL] = [],
        detectedVersion: String? = nil,
        dataRoots: [URL] = [],
        skillRoots: [URL] = [],
        pluginRoots: [URL] = [],
        configDirectories: [URL] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.executableURL = executableURL
        self.aliasExecutableURLs = aliasExecutableURLs
        self.detectedVersion = detectedVersion
        self.dataRoots = dataRoots
        self.skillRoots = skillRoots
        self.pluginRoots = pluginRoots
        self.configDirectories = configDirectories
    }

    // Custom Codable so older snapshots that predate `aliasExecutableURLs`
    // decode without error (defaults to empty) and never break history.
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case applicationURL
        case executableURL
        case aliasExecutableURLs
        case detectedVersion
        case dataRoots
        case skillRoots
        case pluginRoots
        case configDirectories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier = try container.decodeIfPresent(String.self, forKey: .bundleIdentifier)
        applicationURL = try container.decodeIfPresent(URL.self, forKey: .applicationURL)
        executableURL = try container.decodeIfPresent(URL.self, forKey: .executableURL)
        aliasExecutableURLs = try container.decodeIfPresent([URL].self, forKey: .aliasExecutableURLs) ?? []
        detectedVersion = try container.decodeIfPresent(String.self, forKey: .detectedVersion)
        dataRoots = try container.decodeIfPresent([URL].self, forKey: .dataRoots) ?? []
        skillRoots = try container.decodeIfPresent([URL].self, forKey: .skillRoots) ?? []
        pluginRoots = try container.decodeIfPresent([URL].self, forKey: .pluginRoots) ?? []
        configDirectories = try container.decodeIfPresent([URL].self, forKey: .configDirectories) ?? []
    }

    /// Merges another evidence value into this one. Scalar fields prefer an
    /// existing non-nil value; collections are unioned while preserving order
    /// and removing duplicates so repeated discovery passes stay stable.
    public mutating func merge(_ other: AIToolEvidence) {
        bundleIdentifier = bundleIdentifier ?? other.bundleIdentifier
        applicationURL = applicationURL ?? other.applicationURL
        executableURL = executableURL ?? other.executableURL
        aliasExecutableURLs = Self.mergeURLsForDiscovery(aliasExecutableURLs, other.aliasExecutableURLs)
        detectedVersion = detectedVersion ?? other.detectedVersion
        dataRoots = Self.mergeURLsForDiscovery(dataRoots, other.dataRoots)
        skillRoots = Self.mergeURLsForDiscovery(skillRoots, other.skillRoots)
        pluginRoots = Self.mergeURLsForDiscovery(pluginRoots, other.pluginRoots)
        configDirectories = Self.mergeURLsForDiscovery(configDirectories, other.configDirectories)
    }

    static func mergeURLsForDiscovery(_ lhs: [URL], _ rhs: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in lhs + rhs {
            let key = url.standardizedFileURL.path
            if seen.insert(key).inserted {
                result.append(url)
            }
        }
        return result
    }
}

/// A read-only reason a discovery pass could not fully cover an asset. These are
/// retained on the record instead of being discarded so the UI can surface
/// partial results honestly rather than silently dropping them.
public enum AIToolCoverageFailure: String, Codable, Hashable, Sendable {
    case permissionDenied
    case timeout
    case outputTruncated
    case invalidOutput
    case unavailable
}

/// A single normalized, read-only record describing a discovered AI asset.
///
/// The identifier is deterministic: it is derived from the owning definition and
/// a canonical location, so re-running discovery over an unchanged filesystem
/// produces identical IDs (no random UUID snapshot drift).
public struct AIToolRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: AIToolKind
    public let displayName: String
    public let owner: AIToolOwner
    public var evidence: AIToolEvidence
    public var coverageFailures: Set<AIToolCoverageFailure>

    public init(
        id: String,
        kind: AIToolKind,
        displayName: String,
        owner: AIToolOwner,
        evidence: AIToolEvidence = AIToolEvidence(),
        coverageFailures: Set<AIToolCoverageFailure> = []
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.owner = owner
        self.evidence = evidence
        self.coverageFailures = coverageFailures
    }

    /// Builds a deterministic stable identifier from the definition ID, kind and
    /// a canonical location. Callers must pass an already-canonicalized location
    /// (typically `URL.standardizedFileURL.path`) so that logically identical
    /// paths collapse to the same ID.
    public static func stableID(
        kind: AIToolKind,
        owner: AIToolOwner,
        canonicalLocation: String
    ) -> String {
        let ownerToken: String
        switch owner {
        case .tool(let definitionID):
            ownerToken = definitionID
        case .shared:
            ownerToken = "shared"
        }
        return "\(kind.rawValue):\(ownerToken):\(canonicalLocation)"
    }
}
