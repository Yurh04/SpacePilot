import Foundation

/// Finds per-user temporary artifacts whose names are owned by an application's
/// signed bundle namespace. The lookup is deliberately shallow: it inspects
/// only the immediate children of macOS' `C`, `T`, and `X` temporary roots.
public struct ApplicationVolatileArtifactCandidate: Equatable, Sendable {
    public let url: URL
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let ownership: AssociationOwnership

    public init(
        url: URL,
        evidence: AssociationEvidence,
        confidence: AssociationConfidence,
        ownership: AssociationOwnership
    ) {
        self.url = url
        self.evidence = evidence
        self.confidence = confidence
        self.ownership = ownership
    }
}

public struct ApplicationVolatileArtifactFinder: Sendable {
    private static let rootNames = ["C", "T", "X"]

    private let temporaryDirectory: URL

    public init(
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        self.temporaryDirectory = temporaryDirectory
    }

    public func candidates(
        for application: ApplicationRecord,
        identity: ApplicationIdentity,
        fileManager: FileManager = .default
    ) throws -> [ApplicationVolatileArtifactCandidate] {
        try Task.checkCancellation()
        let namespaces = Self.namespaces(
            application: application,
            identity: identity
        )
        guard !namespaces.isEmpty,
              let userRoot = safeUserTemporaryRoot(fileManager: fileManager)
        else {
            return []
        }

        var candidatesByPath: [String: ApplicationVolatileArtifactCandidate] = [:]
        for rootName in Self.rootNames {
            try Task.checkCancellation()
            let root = userRoot.appending(
                path: rootName,
                directoryHint: .isDirectory
            )
            guard let canonicalRoot = safeDirectory(
                at: root,
                within: userRoot,
                fileManager: fileManager
            ), let children = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey
                ],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children {
                try Task.checkCancellation()
                guard let canonicalURL = safeNode(
                    at: child,
                    within: canonicalRoot
                ), let namespace = Self.matchingNamespace(
                    for: canonicalURL.lastPathComponent,
                    in: namespaces
                ) else {
                    continue
                }
                let evidence: AssociationEvidence = namespace.isMain
                    ? .knownRule
                    : .signedHelperRelationship
                candidatesByPath[canonicalURL.path] =
                    ApplicationVolatileArtifactCandidate(
                        url: canonicalURL,
                        evidence: evidence,
                        confidence: .high,
                        ownership: .owned
                    )
            }
        }

        return candidatesByPath.values.sorted {
            $0.url.path.localizedStandardCompare($1.url.path)
                == .orderedAscending
        }
    }

    private struct Namespace: Sendable {
        let identifier: String
        let isMain: Bool
    }

    private static func namespaces(
        application: ApplicationRecord,
        identity: ApplicationIdentity
    ) -> [Namespace] {
        let mainIdentifier = normalizedIdentifier(
            identity.mainBundleIdentifier ?? application.bundleIdentifier
        )
        var seen = Set<String>()
        var result: [Namespace] = []
        if let mainIdentifier, seen.insert(mainIdentifier).inserted {
            result.append(Namespace(
                identifier: mainIdentifier,
                isMain: true
            ))
        }
        for identifier in identity.componentBundleIdentifiers
            .compactMap(normalizedIdentifier)
            .sorted(by: { $0.count > $1.count })
            where seen.insert(identifier).inserted {
            result.append(Namespace(identifier: identifier, isMain: false))
        }
        return result.sorted {
            if $0.identifier.count != $1.identifier.count {
                return $0.identifier.count > $1.identifier.count
            }
            return $0.identifier < $1.identifier
        }
    }

    private static func matchingNamespace(
        for component: String,
        in namespaces: [Namespace]
    ) -> Namespace? {
        let normalizedComponent = component.lowercased()
        return namespaces.first { namespace in
            normalizedComponent == namespace.identifier
                || normalizedComponent.hasPrefix(namespace.identifier + ".")
        }
    }

    private static func normalizedIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased()
        guard normalized.count >= 3,
              normalized.count <= 255,
              normalized.contains("."),
              !normalized.contains("/"),
              !normalized.contains("\\"),
              !normalized.contains("\0")
        else {
            return nil
        }
        return normalized
    }

    private func safeUserTemporaryRoot(
        fileManager: FileManager
    ) -> URL? {
        let temporary = temporaryDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let userRoot = temporary.lastPathComponent == "T"
            ? temporary.deletingLastPathComponent()
            : temporary
        guard let values = try? userRoot.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), values.isDirectory == true,
              values.isSymbolicLink != true,
              fileManager.fileExists(atPath: userRoot.path)
        else {
            return nil
        }
        return userRoot
    }

    private func safeDirectory(
        at url: URL,
        within userRoot: URL,
        fileManager: FileManager
    ) -> URL? {
        guard fileManager.fileExists(atPath: url.path),
              let values = try? url.resourceValues(
                  forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
              ), values.isDirectory == true,
              values.isSymbolicLink != true
        else {
            return nil
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isStrictDescendant(canonicalURL, of: userRoot) else {
            return nil
        }
        return canonicalURL
    }

    private func safeNode(at url: URL, within root: URL) -> URL? {
        guard let values = try? url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ]
        ), values.isSymbolicLink != true,
              values.isDirectory == true || values.isRegularFile == true
        else {
            return nil
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard Self.isStrictDescendant(canonicalURL, of: root) else {
            return nil
        }
        return canonicalURL
    }

    private static func isStrictDescendant(
        _ candidate: URL,
        of root: URL
    ) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
