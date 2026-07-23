import Foundation

public struct CleanupReviewItem: Identifiable, Sendable {
    public var id: UUID { item.id }
    public let item: ScannedItem
    public let ownership: AssociationOwnership
    public let evidence: AssociationEvidence?

    public var isIncludedBySelectAll: Bool { ownership == .owned }

    public init(
        item: ScannedItem,
        ownership: AssociationOwnership,
        evidence: AssociationEvidence?
    ) {
        self.item = item
        self.ownership = ownership
        self.evidence = evidence
    }
}

public struct ApplicationUninstallPlanner: Sendable {
    public init() {}

    public func cleanupItems(for projection: ApplicationProjection) -> [CleanupReviewItem] {
        let application = projection.application
        let values = try? application.url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ])
        let appItem = ScannedItem(
            url: application.url,
            logicalSize: application.allocatedSize,
            allocatedSize: application.allocatedSize,
            creationDate: values?.creationDate,
            modificationDate: values?.contentModificationDate,
            resourceIdentifier: values?.fileResourceIdentifier.map { String(describing: $0) },
            category: .application,
            risk: .rebuildable,
            ownerID: application.id,
            explanation: "Application bundle"
        )
        let appReviewItem = CleanupReviewItem(
            item: appItem,
            ownership: .owned,
            evidence: nil
        )
        let related = uniqueReviewItems(in: projection.associations) {
            $0.association.risk != .managed && $0.item.risk != .managed
        }
        return [appReviewItem] + related.sorted {
            $0.item.allocatedSize > $1.item.allocatedSize
        }
    }

    public func resetItems(for projection: ApplicationProjection) -> [ScannedItem] {
        uniqueItems(in: projection.associations) {
            $0.association.confidence == .high
                && $0.association.ownership == .owned
                && $0.association.risk != .sensitive
                && $0.association.risk != .managed
                && $0.item.risk != .sensitive
                && $0.item.risk != .managed
        }
            .sorted { $0.allocatedSize > $1.allocatedSize }
    }

    private func uniqueReviewItems(
        in associations: [ApplicationAssociationProjection],
        matching predicate: (ApplicationAssociationProjection) -> Bool
    ) -> [CleanupReviewItem] {
        var seenItemIDs: Set<UUID> = []
        return associations.compactMap { pair in
            guard predicate(pair), seenItemIDs.insert(pair.item.id).inserted else { return nil }
            return CleanupReviewItem(
                item: pair.item,
                ownership: pair.association.ownership,
                evidence: pair.association.evidence
            )
        }
    }

    private func uniqueItems(
        in associations: [ApplicationAssociationProjection],
        matching predicate: (ApplicationAssociationProjection) -> Bool
    ) -> [ScannedItem] {
        var seenItemIDs: Set<UUID> = []
        return associations.compactMap { pair in
            guard predicate(pair), seenItemIDs.insert(pair.item.id).inserted else { return nil }
            return pair.item
        }
    }
}
