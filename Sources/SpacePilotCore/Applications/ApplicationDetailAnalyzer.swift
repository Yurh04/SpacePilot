import Foundation

public struct ApplicationDetailAnalysis: Sendable {
    public let applicationID: UUID
    public let items: [ScannedItem]
    public let associations: [ArtifactAssociation]

    public init(
        applicationID: UUID,
        items: [ScannedItem],
        associations: [ArtifactAssociation]
    ) {
        self.applicationID = applicationID
        self.items = items
        self.associations = associations
    }
}

public struct ApplicationDetailAnalyzer: Sendable {
    private struct Candidate: Sendable {
        let url: URL
        let category: ItemCategory
        let risk: RiskLevel
        let evidence: AssociationEvidence
        let confidence: AssociationConfidence
        let ownership: AssociationOwnership
        let explanation: String
    }

    private struct ResolvedCandidate: Sendable {
        let candidate: Candidate
        let size: ApplicationArtifactSize
    }

    private let directoryStats: (any DirectoryStatProviding)?
    private let cache: (any ScanResultCaching)?
    private let identityReader: any ApplicationIdentityReading
    private let spotlightFinder: SpotlightApplicationCandidateFinder
    private let knowledgeBase: ApplicationAssociationKnowledgeBase

    public init(
        directoryStats: (any DirectoryStatProviding)? = nil,
        cache: (any ScanResultCaching)? = nil,
        identityReader: any ApplicationIdentityReading =
            ApplicationIdentityReader(),
        spotlightFinder: SpotlightApplicationCandidateFinder =
            SpotlightApplicationCandidateFinder(),
        knowledgeBase: ApplicationAssociationKnowledgeBase = .builtInV1
    ) {
        self.directoryStats = directoryStats
        self.cache = cache
        self.identityReader = identityReader
        self.spotlightFinder = spotlightFinder
        self.knowledgeBase = knowledgeBase
    }

    public func analyze(
        application: ApplicationRecord,
        homeDirectory: URL,
        indexedItems: [ScannedItem] = [],
        indexedAIApplications: [AIApplicationRecord] = []
    ) async throws -> ApplicationDetailAnalysis {
        try Task.checkCancellation()
        let identity: ApplicationIdentity
        if let cache,
           let cached = try? await cache.cachedApplicationIdentity(
               for: application
           ) {
            identity = cached
        } else {
            identity = try identityReader.read(application: application)
            if let cache {
                try? await cache.save(
                    applicationIdentity: identity,
                    for: application
                )
            }
        }
        try Task.checkCancellation()

        let standardResolution = try await ApplicationArtifactResolver(
            directoryStats: directoryStats
        ).resolve(
            applications: [application],
            identities: [identity],
            homeDirectory: homeDirectory
        )
        let unresolvedStandardItems = standardResolution.items
        let unresolvedStandardAssociations =
            standardResolution.resolutions.first?.associations ?? []

        let spotlightCandidates: [SpotlightApplicationCandidate]
        if Self.usesSpotlightCandidates(for: application) {
            spotlightCandidates = try await spotlightFinder.candidates(
                for: application,
                identity: identity,
                homeDirectory: homeDirectory
            )
        } else {
            spotlightCandidates = []
        }
        let knowledgeCandidates = try knowledgeBase.candidates(
            for: ApplicationAssociationKnowledgeContext(
                applicationName: application.name,
                bundleIdentifier: identity.mainBundleIdentifier
                    ?? application.bundleIdentifier,
                teamIdentifier: identity.teamIdentifier,
                applicationBundleURL: application.url
            ),
            homeDirectory: homeDirectory
        )
        let knowledgeURLs = knowledgeCandidates.map {
            $0.url.standardizedFileURL.resolvingSymlinksInPath()
        }
        let supersededStandardItemIDs = Set(
            unresolvedStandardItems.compactMap { item -> UUID? in
                let itemURL = item.url.standardizedFileURL
                    .resolvingSymlinksInPath()
                return knowledgeURLs.contains(where: {
                    Self.isStrictDescendant(itemURL, of: $0)
                }) ? item.id : nil
            }
        )
        let standardItems = unresolvedStandardItems.filter {
            !supersededStandardItemIDs.contains($0.id)
        }
        let standardAssociations = unresolvedStandardAssociations.filter {
            !supersededStandardItemIDs.contains($0.itemID)
        }
        let occupiedURLs = standardItems.map(\.url)
        let candidates = mergeCandidates(
            spotlight: spotlightCandidates,
            knowledge: knowledgeCandidates,
            excluding: occupiedURLs,
            application: application,
            homeDirectory: homeDirectory
        )
        let resolvedCandidates = try await resolveSizes(candidates)

        var items = standardItems
        var associations = standardAssociations
        items.reserveCapacity(items.count + resolvedCandidates.count)
        associations.reserveCapacity(
            associations.count + resolvedCandidates.count
        )
        for resolved in resolvedCandidates {
            let values = try? resolved.candidate.url.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                    .fileResourceIdentifierKey
                ]
            )
            let item = ScannedItem(
                url: resolved.candidate.url,
                logicalSize: resolved.size.logical,
                allocatedSize: resolved.size.allocated,
                modificationDate: values?.contentModificationDate,
                resourceIdentifier: values?.fileResourceIdentifier.map {
                    String(describing: $0)
                },
                category: resolved.candidate.category,
                risk: resolved.candidate.risk,
                ownerID: resolved.candidate.ownership == .owned
                    ? application.id
                    : nil,
                explanation: resolved.candidate.explanation
            )
            items.append(item)
            associations.append(ArtifactAssociation(
                itemID: item.id,
                applicationID: application.id,
                evidence: resolved.candidate.evidence,
                confidence: resolved.candidate.confidence,
                risk: resolved.candidate.risk,
                ownership: resolved.candidate.ownership
            ))
        }
        let indexedItemsByID = Dictionary(
            uniqueKeysWithValues: indexedItems.map { ($0.id, $0) }
        )
        let existingAssociationItemIDs = Set(associations.map(\.itemID))
        let productFamilyItemIDs = Self.productFamilyItemIDs(
            for: application,
            aiApplications: indexedAIApplications
        )
        for itemID in productFamilyItemIDs.sorted(by: {
            $0.uuidString < $1.uuidString
        }) where !existingAssociationItemIDs.contains(itemID) {
            guard let item = indexedItemsByID[itemID] else { continue }
            associations.append(ArtifactAssociation(
                itemID: itemID,
                applicationID: application.id,
                evidence: .knownRule,
                confidence: .high,
                risk: item.risk,
                ownership: .shared
            ))
        }
        return ApplicationDetailAnalysis(
            applicationID: application.id,
            items: items,
            associations: associations
        )
    }

    private static func usesSpotlightCandidates(
        for application: ApplicationRecord
    ) -> Bool {
        application.bundleIdentifier?.lowercased() != "com.openai.codex"
    }

    private static func productFamilyItemIDs(
        for application: ApplicationRecord,
        aiApplications: [AIApplicationRecord]
    ) -> Set<UUID> {
        let bundleIdentifier = application.bundleIdentifier?.lowercased()
        return aiApplications.reduce(into: Set<UUID>()) { result, aiApplication in
            let sameBundleIdentifier = bundleIdentifier != nil
                && aiApplication.bundleIdentifier?.lowercased()
                    == bundleIdentifier
            let sameApplicationURL = aiApplication.applicationURL?
                .standardizedFileURL == application.url.standardizedFileURL
            if sameBundleIdentifier || sameApplicationURL {
                result.formUnion(aiApplication.itemIDs)
            }
        }
    }

    private func mergeCandidates(
        spotlight: [SpotlightApplicationCandidate],
        knowledge: [ApplicationAssociationKnowledgeCandidate],
        excluding occupiedURLs: [URL],
        application: ApplicationRecord,
        homeDirectory: URL
    ) -> [Candidate] {
        let applicationURL = application.url.standardizedFileURL
            .resolvingSymlinksInPath()
        var candidates: [Candidate] = knowledge.compactMap { candidate in
            guard candidate.excludedURLs.allSatisfy({
                !FileManager.default.fileExists(atPath: $0.path)
            }) else {
                return nil
            }
            return Candidate(
                url: candidate.url,
                category: candidate.category,
                risk: candidate.risk,
                evidence: candidate.evidence,
                confidence: candidate.confidence,
                ownership: candidate.ownership,
                explanation: "Matched local knowledge rule \(candidate.ruleID)"
            )
        }
        candidates.append(contentsOf: spotlight.map {
            Candidate(
                url: $0.url,
                category: Self.category(for: $0.url, homeDirectory: homeDirectory),
                risk: Self.risk(
                    for: $0.url,
                    confidence: $0.confidence,
                    homeDirectory: homeDirectory
                ),
                evidence: $0.evidence,
                confidence: $0.confidence,
                ownership: $0.confidence == .high ? .owned : .possible,
                explanation: "Discovered from the local Spotlight index"
            )
        })

        let occupied = occupiedURLs.map {
            $0.standardizedFileURL.resolvingSymlinksInPath()
        }
        let ordered = candidates.sorted {
            if $0.confidence != $1.confidence {
                return $0.confidence > $1.confidence
            }
            return $0.url.pathComponents.count < $1.url.pathComponents.count
        }
        var accepted: [Candidate] = []
        var paths = Set<String>()
        for candidate in ordered {
            let url = candidate.url.standardizedFileURL
            let canonicalURL = url.resolvingSymlinksInPath()
            guard FileManager.default.fileExists(atPath: url.path),
                  !Self.isSameOrDescendant(canonicalURL, of: applicationURL),
                  !occupied.contains(where: {
                      Self.overlaps(canonicalURL, $0)
                  }),
                  !accepted.contains(where: {
                      Self.overlaps(canonicalURL, $0.url)
                  }),
                  paths.insert(canonicalURL.path).inserted,
                  (try? url.resourceValues(
                      forKeys: [.isSymbolicLinkKey]
                  ).isSymbolicLink) != true
            else {
                continue
            }
            accepted.append(Candidate(
                url: canonicalURL,
                category: candidate.category,
                risk: candidate.risk,
                evidence: candidate.evidence,
                confidence: candidate.confidence,
                ownership: candidate.ownership,
                explanation: candidate.explanation
            ))
        }
        return accepted.sorted {
            $0.url.path.localizedStandardCompare($1.url.path)
                == .orderedAscending
        }
    }

    private func resolveSizes(
        _ candidates: [Candidate]
    ) async throws -> [ResolvedCandidate] {
        try await withThrowingTaskGroup(of: ResolvedCandidate.self) { group in
            var iterator = candidates.makeIterator()
            var results: [ResolvedCandidate] = []
            results.reserveCapacity(candidates.count)

            for _ in 0..<min(4, candidates.count) {
                guard let candidate = iterator.next() else { break }
                group.addTask { try await resolveSize(candidate) }
            }
            while let result = try await group.next() {
                results.append(result)
                if let candidate = iterator.next() {
                    group.addTask { try await resolveSize(candidate) }
                }
            }
            return results.sorted {
                $0.candidate.url.path.localizedStandardCompare(
                    $1.candidate.url.path
                ) == .orderedAscending
            }
        }
    }

    private func resolveSize(_ candidate: Candidate) async throws
        -> ResolvedCandidate
    {
        if let cached = try await directoryStats?.cachedDirectoryStat(
            at: candidate.url
        ) {
            return ResolvedCandidate(
                candidate: candidate,
                size: ApplicationArtifactSize(
                    logical: cached.totalLogicalSize,
                    allocated: cached.totalAllocatedSize
                )
            )
        }
        return ResolvedCandidate(
            candidate: candidate,
            size: try await FileSystemApplicationArtifactSizeResolver()
                .sizes(of: candidate.url)
        )
    }

    private static func overlaps(_ lhs: URL, _ rhs: URL) -> Bool {
        isSameOrDescendant(lhs, of: rhs) || isSameOrDescendant(rhs, of: lhs)
    }

    private static func isStrictDescendant(_ url: URL, of root: URL) -> Bool {
        url.standardizedFileURL.path != root.standardizedFileURL.path
            && isSameOrDescendant(url, of: root)
    }

    private static func isSameOrDescendant(_ url: URL, of root: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let rootPath = root.standardizedFileURL.path
        return path == rootPath || path.hasPrefix(
            rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        )
    }

    private static func category(
        for url: URL,
        homeDirectory: URL
    ) -> ItemCategory {
        let relative = url.path.replacingOccurrences(
            of: homeDirectory.path + "/",
            with: ""
        )
        if relative.hasPrefix("Library/Caches/") { return .cache }
        if relative.hasPrefix("Library/Logs/") { return .log }
        if relative.hasPrefix("Library/Developer/") { return .developer }
        return .application
    }

    private static func risk(
        for url: URL,
        confidence: AssociationConfidence,
        homeDirectory: URL
    ) -> RiskLevel {
        guard confidence == .high else { return .sensitive }
        switch category(for: url, homeDirectory: homeDirectory) {
        case .cache, .log:
            return .rebuildable
        default:
            return .sensitive
        }
    }
}
