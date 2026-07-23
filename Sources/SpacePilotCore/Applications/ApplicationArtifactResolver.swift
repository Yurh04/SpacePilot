import Foundation

public struct ApplicationArtifactResolution: Sendable {
    public let items: [ScannedItem]
    public let associations: [ArtifactAssociation]

    public init(items: [ScannedItem], associations: [ArtifactAssociation]) {
        self.items = items
        self.associations = associations
    }
}

public struct ApplicationResolution: Sendable {
    public let applicationID: UUID
    public let associations: [ArtifactAssociation]

    public init(
        applicationID: UUID,
        associations: [ArtifactAssociation]
    ) {
        self.applicationID = applicationID
        self.associations = associations
    }
}

public struct ApplicationArtifactBatchResolution: Sendable {
    public let items: [ScannedItem]
    public let resolutions: [ApplicationResolution]

    public init(
        items: [ScannedItem],
        resolutions: [ApplicationResolution]
    ) {
        self.items = items
        self.resolutions = resolutions
    }
}

public struct ApplicationArtifactResolver: Sendable {
    private struct Match: Sendable {
        let evidence: AssociationEvidence
        let confidence: AssociationConfidence
        let ownership: AssociationOwnership
        let explanation: String
    }

    private struct Candidate {
        let url: URL
        var rule: ApplicationArtifactRoot
        var rootDepth: Int
        var matchesByApplicationID: [UUID: Match]
    }

    private struct ResolvedRoot {
        let rule: ApplicationArtifactRoot
        let url: URL
        let canonicalURL: URL
    }

    private let roots: [ApplicationArtifactRoot]

    public init(roots: [ApplicationArtifactRoot] = ApplicationArtifactRoot.standard) {
        self.roots = roots
    }

    public func resolve(
        applications: [ApplicationRecord],
        identities: [ApplicationIdentity],
        homeDirectory: URL
    ) async throws -> ApplicationArtifactBatchResolution {
        let identityByApplicationID = Dictionary(
            identities.map { ($0.applicationID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let groupOwnerCounts = identities
            .flatMap { $0.applicationGroups }
            .reduce(into: [String: Int]()) {
                $0[$1, default: 0] += 1
            }
        let canonicalHome = homeDirectory.standardizedFileURL
            .resolvingSymlinksInPath()
        let resolvedRoots = roots.compactMap { rule -> ResolvedRoot? in
            let url = homeDirectory.appending(
                path: rule.relativePath,
                directoryHint: .isDirectory
            ).standardizedFileURL
            guard let canonicalURL = safeDirectory(
                at: url,
                strictlyWithin: canonicalHome
            ) else {
                return nil
            }
            return ResolvedRoot(
                rule: rule,
                url: url,
                canonicalURL: canonicalURL
            )
        }
        let configuredRootPaths = Set(resolvedRoots.map { $0.url.path })
        var candidatesByPath: [String: Candidate] = [:]

        for root in resolvedRoots {
            try Task.checkCancellation()
            try discoverCandidates(
                in: root,
                applications: applications,
                identityByApplicationID: identityByApplicationID,
                groupOwnerCounts: groupOwnerCounts,
                configuredRootPaths: configuredRootPaths,
                candidatesByPath: &candidatesByPath
            )
        }

        var associationsByApplicationID = Dictionary(
            uniqueKeysWithValues: applications.map { ($0.id, [ArtifactAssociation]()) }
        )
        var items: [ScannedItem] = []

        for candidate in candidatesByPath.values.sorted(by: {
            $0.url.path < $1.url.path
        }) {
            try Task.checkCancellation()
            let sizes = try sizes(of: candidate.url)
            let resourceValues = try? candidate.url.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                    .fileResourceIdentifierKey
                ]
            )
            let collectedMatches = candidate.matchesByApplicationID.sorted {
                $0.key.uuidString < $1.key.uuidString
            }
            let hasSharedExactIdentifier = collectedMatches.lazy.filter {
                $0.value.evidence == .exactBundleIdentifier
                    && $0.value.ownership == .owned
            }.count > 1
            let matches: [(key: UUID, value: Match)] = collectedMatches.map {
                applicationID, match in
                guard hasSharedExactIdentifier,
                      match.evidence == .exactBundleIdentifier,
                      match.ownership == .owned
                else {
                    return (key: applicationID, value: match)
                }
                return (
                    key: applicationID,
                    value: Match(
                        evidence: match.evidence,
                        confidence: match.confidence,
                        ownership: .shared,
                        explanation: match.explanation
                    )
                )
            }
            let ownerID: UUID?
            if matches.count == 1, matches[0].value.ownership == .owned {
                ownerID = matches[0].key
            } else {
                ownerID = nil
            }
            let explanation: String
            if matches.count == 1 {
                explanation = matches[0].value.explanation
            } else {
                explanation = "Matched multiple applications in a known service directory"
            }
            let item = ScannedItem(
                url: candidate.url,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                modificationDate: resourceValues?.contentModificationDate,
                resourceIdentifier: resourceValues?.fileResourceIdentifier.map {
                    String(describing: $0)
                },
                category: candidate.rule.category,
                risk: candidate.rule.risk,
                ownerID: ownerID,
                explanation: explanation
            )
            items.append(item)

            for (applicationID, match) in matches {
                associationsByApplicationID[applicationID, default: []].append(
                    ArtifactAssociation(
                        itemID: item.id,
                        applicationID: applicationID,
                        evidence: match.evidence,
                        confidence: match.confidence,
                        risk: candidate.rule.risk,
                        ownership: match.ownership
                    )
                )
            }
        }

        return ApplicationArtifactBatchResolution(
            items: items,
            resolutions: applications.map {
                ApplicationResolution(
                    applicationID: $0.id,
                    associations: associationsByApplicationID[$0.id, default: []]
                )
            }
        )
    }

    public func resolve(
        application: ApplicationRecord,
        homeDirectory: URL
    ) async throws -> ApplicationArtifactResolution {
        let identity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: [],
            teamIdentifier: nil,
            applicationGroups: []
        )
        let batch = try await resolve(
            applications: [application],
            identities: [identity],
            homeDirectory: homeDirectory
        )
        return ApplicationArtifactResolution(
            items: batch.items,
            associations: batch.resolutions.first?.associations ?? []
        )
    }

    private func discoverCandidates(
        in root: ResolvedRoot,
        applications: [ApplicationRecord],
        identityByApplicationID: [UUID: ApplicationIdentity],
        groupOwnerCounts: [String: Int],
        configuredRootPaths: Set<String>,
        candidatesByPath: inout [String: Candidate]
    ) throws {
        let maximumDepth = root.rule.relativePath
            == "Library/Application Support" ? 2 : 1
        var pending = [(directory: root.url, depth: 0)]

        while let (directory, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory,
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
                guard let node = safeNode(
                    at: child,
                    strictlyWithin: root.canonicalURL
                ) else {
                    continue
                }
                guard !configuredRootPaths.contains(node.url.path) else {
                    continue
                }
                let childDepth = depth + 1
                let matches = applications.compactMap {
                    application -> (UUID, Match)? in
                    guard let identity = identityByApplicationID[application.id],
                          let match = match(
                              child: node.url,
                              application: application,
                              identity: identity,
                              groupOwnerCounts: groupOwnerCounts
                          )
                    else {
                        return nil
                    }
                    return (application.id, match)
                }

                if !matches.isEmpty {
                    merge(
                        url: node.url,
                        rule: root.rule,
                        rootDepth: root.canonicalURL.pathComponents.count,
                        matches: matches,
                        into: &candidatesByPath
                    )
                    continue
                }

                guard node.isDirectory, childDepth < maximumDepth else {
                    continue
                }
                pending.append((node.url, childDepth))
            }
        }
    }

    private func merge(
        url: URL,
        rule: ApplicationArtifactRoot,
        rootDepth: Int,
        matches: [(UUID, Match)],
        into candidatesByPath: inout [String: Candidate]
    ) {
        let path = url.standardizedFileURL.path
        var candidate = candidatesByPath[path] ?? Candidate(
            url: url.standardizedFileURL,
            rule: rule,
            rootDepth: rootDepth,
            matchesByApplicationID: [:]
        )
        if rootDepth > candidate.rootDepth {
            candidate.rule = rule
            candidate.rootDepth = rootDepth
        }
        for (applicationID, match) in matches {
            if let current = candidate.matchesByApplicationID[applicationID],
               current.confidence >= match.confidence {
                continue
            }
            candidate.matchesByApplicationID[applicationID] = match
        }
        candidatesByPath[path] = candidate
    }

    private func match(
        child: URL,
        application: ApplicationRecord,
        identity: ApplicationIdentity,
        groupOwnerCounts: [String: Int]
    ) -> Match? {
        let component = child.lastPathComponent
        let stem = child.deletingPathExtension().lastPathComponent
        if identity.allBundleIdentifiers.contains(component)
            || identity.allBundleIdentifiers.contains(stem) {
            return Match(
                evidence: .exactBundleIdentifier,
                confidence: .high,
                ownership: .owned,
                explanation: "Exact bundle identifier match: \(stem)"
            )
        }
        if identity.applicationGroups.contains(component) {
            let isExclusive = groupOwnerCounts[component, default: 0] == 1
                && identity.allBundleIdentifiers.contains {
                    component.contains($0)
                }
            let ownership: AssociationOwnership = isExclusive
                ? .owned
                : .shared
            return Match(
                evidence: .exactContainerIdentifier,
                confidence: .high,
                ownership: ownership,
                explanation: "Exact application group match: \(component)"
            )
        }

        let normalizedApplicationName = normalize(application.name)
        let normalizedComponent = normalize(stem)
        if normalizedComponent == normalizedApplicationName {
            return Match(
                evidence: .vendorAndNameMatch,
                confidence: .medium,
                ownership: .possible,
                explanation: "Application name match in a known service directory"
            )
        }
        return nil
    }

    private func normalize(_ value: String) -> String {
        value.lowercased().replacingOccurrences(of: " ", with: "")
    }

    private func sizes(of root: URL) throws -> (
        logical: Int64,
        allocated: Int64
    ) {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        let rootValues = try? root.resourceValues(forKeys: keys)
        if rootValues?.isRegularFile == true,
           rootValues?.isSymbolicLink != true {
            return (
                Int64(rootValues?.fileSize ?? 0),
                Int64(rootValues?.totalFileAllocatedSize ?? 0)
            )
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return (0, 0)
        }
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var processed = 0
        for case let url as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                continue
            }
            logical += Int64(values.fileSize ?? 0)
            allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        try Task.checkCancellation()
        return (logical, allocated)
    }

    private func safeDirectory(
        at url: URL,
        strictlyWithin root: URL
    ) -> URL? {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), values.isDirectory == true, values.isSymbolicLink != true
        else {
            return nil
        }
        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isStrictDescendant(canonicalURL, of: root) else {
            return nil
        }
        return canonicalURL
    }

    private func safeNode(
        at url: URL,
        strictlyWithin root: URL
    ) -> (url: URL, isDirectory: Bool)? {
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
        guard isStrictDescendant(canonicalURL, of: root) else {
            return nil
        }
        return (url.standardizedFileURL, values.isDirectory == true)
    }

    private func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }
}
