import Foundation

struct AIAssetByteBreakdown: Sendable, Equatable {
    let applicationBytes: Int64
    let dataItemBytes: Int64
    let pluginBytes: Int64
    let standaloneSkillBytes: Int64

    var total: Int64 {
        applicationBytes + dataItemBytes + pluginBytes + standaloneSkillBytes
    }
}

private enum AIManagedAssetKind: Int, Sendable {
    case plugin
    case standaloneSkill
}

private struct AIManagedAssetCandidate: Sendable {
    let kind: AIManagedAssetKind
    let url: URL
    let allocatedSize: Int64
}

enum AIAssetByteOwnership {
    static func aggregate<Items: Sequence, Plugins: Sequence, Skills: Sequence>(
        applicationBytes: Int64,
        items: Items,
        plugins: Plugins,
        skills: Skills,
        ownedPluginIDs: Set<UUID>
    ) -> AIAssetByteBreakdown where
        Items.Element == ScannedItem,
        Plugins.Element == PluginRecord,
        Skills.Element == SkillRecord
    {
        try! aggregate(
            applicationBytes: applicationBytes,
            items: items,
            plugins: plugins,
            skills: skills,
            ownedPluginIDs: ownedPluginIDs,
            checkCancellation: {}
        )
    }

    static func aggregate<Items: Sequence, Plugins: Sequence, Skills: Sequence>(
        applicationBytes: Int64,
        items: Items,
        plugins: Plugins,
        skills: Skills,
        ownedPluginIDs: Set<UUID>,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws -> AIAssetByteBreakdown where
        Items.Element == ScannedItem,
        Plugins.Element == PluginRecord,
        Skills.Element == SkillRecord
    {
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var candidates: [AIManagedAssetCandidate] = []
        for plugin in plugins {
            try checkpoint.checkPeriodically()
            candidates.append(AIManagedAssetCandidate(
                kind: .plugin,
                url: plugin.url,
                allocatedSize: plugin.allocatedSize
            ))
        }
        for skill in skills {
            try checkpoint.checkPeriodically()
            if let parentPluginID = skill.parentPluginID,
               ownedPluginIDs.contains(parentPluginID) {
                continue
            }
            candidates.append(AIManagedAssetCandidate(
                kind: .standaloneSkill,
                url: skill.url,
                allocatedSize: skill.allocatedSize
            ))
        }

        let managedAssets = try AIManagedAssetOwnership(
            candidates: candidates,
            checkCancellation: checkCancellation
        )
        var dataItemBytes: Int64 = 0
        for item in items {
            try checkpoint.checkPeriodically()
            if item.category != .plugin,
               item.category != .skill,
               !managedAssets.contains(item.url) {
                dataItemBytes += item.allocatedSize
            }
        }
        try checkCancellation()
        return AIAssetByteBreakdown(
            applicationBytes: applicationBytes,
            dataItemBytes: dataItemBytes,
            pluginBytes: managedAssets.pluginBytes,
            standaloneSkillBytes: managedAssets.standaloneSkillBytes
        )
    }
}

/// Assigns each physical managed directory to one aggregate component and provides
/// component-safe containment checks for the file-level rows scanned beneath it.
private struct AIManagedAssetOwnership: Sendable {
    let pluginBytes: Int64
    let standaloneSkillBytes: Int64

    private let knownRoots: Set<String>

    init(
        candidates: [AIManagedAssetCandidate],
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        struct NormalizedCandidate {
            let candidate: AIManagedAssetCandidate
            let standardizedURL: URL
            let canonicalURL: URL
        }

        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var normalized: [NormalizedCandidate] = []
        normalized.reserveCapacity(candidates.count)
        for candidate in candidates {
            try checkpoint.checkPeriodically()
            let standardizedURL = candidate.url.standardizedFileURL
            let canonicalURL = FileManager.default.fileExists(atPath: standardizedURL.path)
                ? standardizedURL.resolvingSymlinksInPath()
                : standardizedURL
            normalized.append(NormalizedCandidate(
                candidate: candidate,
                standardizedURL: standardizedURL,
                canonicalURL: canonicalURL
            ))
        }
        normalized = try ProjectionCancellationAwareOrdering.sorted(
            normalized,
            by: { lhs, rhs in
                let lhsDepth = lhs.canonicalURL.pathComponents.count
                let rhsDepth = rhs.canonicalURL.pathComponents.count
                if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
                if lhs.canonicalURL.path != rhs.canonicalURL.path {
                    return lhs.canonicalURL.path < rhs.canonicalURL.path
                }
                return lhs.candidate.kind.rawValue < rhs.candidate.kind.rawValue
            },
            checkCancellation: checkCancellation
        )

        var acceptedCanonicalRoots: Set<String> = []
        var knownRoots: Set<String> = []
        var pluginBytes: Int64 = 0
        var standaloneSkillBytes: Int64 = 0
        for entry in normalized {
            try checkpoint.checkPeriodically()
            let isAlreadyOwned = Self.contains(
                entry.canonicalURL.path,
                in: acceptedCanonicalRoots
            )

            // Store both bounded root spellings so item classification remains a
            // lexical lookup with no filesystem access on the potentially huge list.
            knownRoots.insert(entry.standardizedURL.path)
            knownRoots.insert(entry.canonicalURL.path)
            guard !isAlreadyOwned else { continue }

            acceptedCanonicalRoots.insert(entry.canonicalURL.path)
            switch entry.candidate.kind {
            case .plugin:
                pluginBytes += entry.candidate.allocatedSize
            case .standaloneSkill:
                standaloneSkillBytes += entry.candidate.allocatedSize
            }
        }

        self.pluginBytes = pluginBytes
        self.standaloneSkillBytes = standaloneSkillBytes
        self.knownRoots = knownRoots
    }

    func contains(_ url: URL) -> Bool {
        Self.contains(url.standardizedFileURL.path, in: knownRoots)
    }

    private static func contains(_ path: String, in roots: Set<String>) -> Bool {
        guard !roots.isEmpty else { return false }
        var current = path
        while true {
            if roots.contains(current) { return true }
            guard current != "/", let separator = current.lastIndex(of: "/") else {
                return false
            }
            current = separator == current.startIndex ? "/" : String(current[..<separator])
        }
    }
}
