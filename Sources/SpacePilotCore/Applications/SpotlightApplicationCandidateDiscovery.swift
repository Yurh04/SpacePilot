import CoreServices
import Foundation

/// A bounded Spotlight lookup. The query layer deliberately returns URLs only:
/// recursive size calculation belongs to the artifact resolver.
public enum SpotlightApplicationCandidateQuery: Hashable, Sendable {
    case bundleIdentifier(String)
    case applicationGroup(String)
    case nameFragment(String)
}

public protocol SpotlightApplicationCandidateQuerying: Sendable {
    func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL]
}

public enum SpotlightApplicationCandidateReason: Equatable, Sendable {
    case mainBundleIdentifier(String)
    case componentBundleIdentifier(String)
    case applicationGroup(String)
    case applicationName(String)
}

public struct SpotlightApplicationCandidate: Equatable, Sendable {
    public let url: URL
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let reason: SpotlightApplicationCandidateReason

    public init(
        url: URL,
        evidence: AssociationEvidence,
        confidence: AssociationConfidence,
        reason: SpotlightApplicationCandidateReason
    ) {
        self.url = url
        self.evidence = evidence
        self.confidence = confidence
        self.reason = reason
    }
}

public enum SpotlightApplicationCandidateQueryError: Error, Sendable {
    case queryCreationFailed
    case queryExecutionFailed
}

/// Production query implementation backed by a synchronous, non-live MDQuery.
///
/// `MDQuery` is used instead of a live metadata query so this type never
/// retains observers, result objects, or a run loop after a lookup completes.
public struct SystemSpotlightApplicationCandidateQuery:
    SpotlightApplicationCandidateQuerying
{
    public init() {}

    public func urls(
        matching query: SpotlightApplicationCandidateQuery,
        in scopes: [URL],
        limit: Int
    ) async throws -> [URL] {
        guard limit > 0, !scopes.isEmpty else { return [] }
        try Task.checkCancellation()

        let queryString = Self.queryString(for: query)
        guard let metadataQuery = MDQueryCreate(
            kCFAllocatorDefault,
            queryString as CFString,
            [kMDItemPath as Any] as CFArray,
            nil
        ) else {
            throw SpotlightApplicationCandidateQueryError.queryCreationFailed
        }

        let scopePaths = scopes.map(\.path) as CFArray
        MDQuerySetSearchScope(metadataQuery, scopePaths, 0)
        MDQuerySetMaxCount(metadataQuery, CFIndex(limit))
        guard MDQueryExecute(
            metadataQuery,
            CFOptionFlags(kMDQuerySynchronous.rawValue)
        ) else {
            throw SpotlightApplicationCandidateQueryError.queryExecutionFailed
        }

        let resultCount = min(Int(MDQueryGetResultCount(metadataQuery)), limit)
        var urls: [URL] = []
        urls.reserveCapacity(resultCount)

        for index in 0..<resultCount {
            try Task.checkCancellation()
            guard let rawResult = MDQueryGetResultAtIndex(
                metadataQuery,
                CFIndex(index)
            ) else {
                continue
            }
            let metadataItem = unsafeBitCast(rawResult, to: MDItem.self)
            guard let path = MDItemCopyAttribute(
                metadataItem,
                kMDItemPath
            ) as? String else {
                continue
            }
            urls.append(URL(fileURLWithPath: path))
        }

        return urls
    }

    private static func queryString(
        for query: SpotlightApplicationCandidateQuery
    ) -> String {
        switch query {
        case let .bundleIdentifier(identifier):
            let literal = escapedQueryLiteral(identifier)
            return """
            (kMDItemCFBundleIdentifier == '\(literal)'cd) || \
            (kMDItemFSName == '\(literal)'cd) || \
            (kMDItemFSName == '\(literal).*'cd)
            """
        case let .applicationGroup(identifier):
            let literal = escapedQueryLiteral(identifier)
            return """
            (kMDItemFSName == '\(literal)'cd) || \
            (kMDItemFSName == '\(literal).*'cd)
            """
        case let .nameFragment(name):
            return "kMDItemFSName == '*\(escapedQueryLiteral(name))*'cd"
        }
    }

    private static func escapedQueryLiteral(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "\\", "'", "\"", "*", "?", "[", "]":
                escaped.append("\\")
                escaped.append(character)
            default:
                escaped.append(character)
            }
        }
        return escaped
    }
}

/// Discovers application-related paths without reading file contents or
/// calculating recursive sizes.
public struct SpotlightApplicationCandidateFinder: Sendable {
    private struct Lookup: Sendable {
        let query: SpotlightApplicationCandidateQuery
        let evidence: AssociationEvidence
        let confidence: AssociationConfidence
        let reason: SpotlightApplicationCandidateReason
    }

    public static let defaultMaximumCandidates = 200
    public static let absoluteMaximumCandidates = 1_000

    private static let maximumComponentIdentifiers = 32
    private static let maximumApplicationGroups = 16

    private let query: any SpotlightApplicationCandidateQuerying
    private let maximumCandidates: Int
    private let includesFuzzyNameMatch: Bool

    public init(
        query: any SpotlightApplicationCandidateQuerying =
            SystemSpotlightApplicationCandidateQuery(),
        maximumCandidates: Int = Self.defaultMaximumCandidates,
        includesFuzzyNameMatch: Bool = true
    ) {
        self.query = query
        self.maximumCandidates = min(
            max(1, maximumCandidates),
            Self.absoluteMaximumCandidates
        )
        self.includesFuzzyNameMatch = includesFuzzyNameMatch
    }

    public func candidates(
        for application: ApplicationRecord,
        identity: ApplicationIdentity,
        homeDirectory: URL
    ) async throws -> [SpotlightApplicationCandidate] {
        let safeRoots = Self.safeSearchRoots(homeDirectory: homeDirectory)
        guard !safeRoots.isEmpty else { return [] }

        var candidatesByPath: [String: SpotlightApplicationCandidate] = [:]
        for lookup in lookups(for: application, identity: identity) {
            try Task.checkCancellation()
            let remaining = maximumCandidates - candidatesByPath.count
            guard remaining > 0 else { break }

            let urls = try await query.urls(
                matching: lookup.query,
                in: safeRoots,
                limit: remaining
            )
            for url in urls {
                guard candidatesByPath.count < maximumCandidates,
                      let safeURL = Self.safeURL(url, within: safeRoots)
                else {
                    continue
                }
                let path = safeURL.path
                guard candidatesByPath[path] == nil else { continue }
                candidatesByPath[path] = SpotlightApplicationCandidate(
                    url: safeURL,
                    evidence: lookup.evidence,
                    confidence: lookup.confidence,
                    reason: lookup.reason
                )
            }
        }

        return candidatesByPath.values.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            if Self.reasonPriority($0.reason) != Self.reasonPriority($1.reason) {
                return Self.reasonPriority($0.reason)
                    < Self.reasonPriority($1.reason)
            }
            return $0.url.path.localizedStandardCompare($1.url.path)
                == .orderedAscending
        }
    }

    private func lookups(
        for application: ApplicationRecord,
        identity: ApplicationIdentity
    ) -> [Lookup] {
        var result: [Lookup] = []
        var seenBundleIdentifiers = Set<String>()

        if let mainIdentifier = normalizedIdentifier(
            identity.mainBundleIdentifier ?? application.bundleIdentifier
        ) {
            seenBundleIdentifiers.insert(mainIdentifier)
            result.append(
                Lookup(
                    query: .bundleIdentifier(mainIdentifier),
                    evidence: .exactBundleIdentifier,
                    confidence: .high,
                    reason: .mainBundleIdentifier(mainIdentifier)
                )
            )
        }

        let componentIdentifiers = identity.componentBundleIdentifiers
            .compactMap(normalizedIdentifier)
            .filter { seenBundleIdentifiers.insert($0).inserted }
            .sorted()
            .prefix(Self.maximumComponentIdentifiers)
        for identifier in componentIdentifiers {
            result.append(
                Lookup(
                    query: .bundleIdentifier(identifier),
                    evidence: .signedHelperRelationship,
                    confidence: .high,
                    reason: .componentBundleIdentifier(identifier)
                )
            )
        }

        let groups = identity.applicationGroups
            .compactMap(normalizedIdentifier)
            .sorted()
            .prefix(Self.maximumApplicationGroups)
        for group in groups {
            result.append(
                Lookup(
                    query: .applicationGroup(group),
                    evidence: .exactContainerIdentifier,
                    confidence: .high,
                    reason: .applicationGroup(group)
                )
            )
        }

        let name = application.name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        if includesFuzzyNameMatch, name.count >= 3 {
            result.append(
                Lookup(
                    query: .nameFragment(name),
                    evidence: .vendorAndNameMatch,
                    confidence: .low,
                    reason: .applicationName(name)
                )
            )
        }
        return result
    }

    private func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 255 else { return nil }
        return normalized
    }

    private static func safeSearchRoots(homeDirectory: URL) -> [URL] {
        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        return ApplicationArtifactRoot.standard
            .map {
                home.appending(
                    path: $0.relativePath,
                    directoryHint: .isDirectory
                )
                .standardizedFileURL
                .resolvingSymlinksInPath()
            }
            .reduce(into: [URL]()) { roots, candidate in
                guard isStrictDescendant(candidate, of: home),
                      !roots.contains(candidate)
                else {
                    return
                }
                roots.append(candidate)
            }
    }

    private static func safeURL(_ url: URL, within roots: [URL]) -> URL? {
        guard url.isFileURL, url.host == nil || url.host == "localhost" else {
            return nil
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard roots.contains(where: {
            canonicalURL == $0 || isStrictDescendant(canonicalURL, of: $0)
        }) else {
            return nil
        }
        return canonicalURL
    }

    private static func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.prefix(rootComponents.count)
                == rootComponents[...]
    }

    private static func reasonPriority(
        _ reason: SpotlightApplicationCandidateReason
    ) -> Int {
        switch reason {
        case .mainBundleIdentifier: 0
        case .componentBundleIdentifier: 1
        case .applicationGroup: 2
        case .applicationName: 3
        }
    }
}
