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
    public var detectedVersion: String?
    public var dataRoots: [URL]
    public var skillRoots: [URL]
    public var pluginRoots: [URL]
    public var configDirectories: [URL]

    public init(
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil,
        executableURL: URL? = nil,
        detectedVersion: String? = nil,
        dataRoots: [URL] = [],
        skillRoots: [URL] = [],
        pluginRoots: [URL] = [],
        configDirectories: [URL] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.executableURL = executableURL
        self.detectedVersion = detectedVersion
        self.dataRoots = dataRoots
        self.skillRoots = skillRoots
        self.pluginRoots = pluginRoots
        self.configDirectories = configDirectories
    }

    /// Merges another evidence value into this one. Scalar fields prefer an
    /// existing non-nil value; collections are unioned while preserving order
    /// and removing duplicates so repeated discovery passes stay stable.
    public mutating func merge(_ other: AIToolEvidence) {
        bundleIdentifier = bundleIdentifier ?? other.bundleIdentifier
        applicationURL = applicationURL ?? other.applicationURL
        executableURL = executableURL ?? other.executableURL
        detectedVersion = detectedVersion ?? other.detectedVersion
        dataRoots = Self.mergeURLs(dataRoots, other.dataRoots)
        skillRoots = Self.mergeURLs(skillRoots, other.skillRoots)
        pluginRoots = Self.mergeURLs(pluginRoots, other.pluginRoots)
        configDirectories = Self.mergeURLs(configDirectories, other.configDirectories)
    }

    private static func mergeURLs(_ lhs: [URL], _ rhs: [URL]) -> [URL] {
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
