import Foundation

public struct CleanupReviewItem: Identifiable, Sendable {
    public var id: UUID { item.id }
    public let item: ScannedItem
    public let ownership: AssociationOwnership
    public let evidence: AssociationEvidence?
    public let effectiveRisk: RiskLevel

    public var isIncludedBySelectAll: Bool {
        ownership == .owned && effectiveRisk != .managed
    }

    public init(
        item: ScannedItem,
        ownership: AssociationOwnership,
        evidence: AssociationEvidence?,
        effectiveRisk: RiskLevel? = nil
    ) {
        let risk = max(item.risk, effectiveRisk ?? item.risk)
        self.item = Self.copy(item, replacingRiskWith: risk)
        self.ownership = ownership
        self.evidence = evidence
        self.effectiveRisk = risk
    }

    private static func copy(
        _ item: ScannedItem,
        replacingRiskWith risk: RiskLevel
    ) -> ScannedItem {
        guard item.risk != risk else { return item }
        return ScannedItem(
            id: item.id,
            url: item.url,
            logicalSize: item.logicalSize,
            allocatedSize: item.allocatedSize,
            creationDate: item.creationDate,
            modificationDate: item.modificationDate,
            resourceIdentifier: item.resourceIdentifier,
            category: item.category,
            risk: risk,
            ownerID: item.ownerID,
            explanation: item.explanation
        )
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
        let related = reviewItems(in: projection.associations)
        return [appReviewItem] + related.sorted {
            if $0.item.allocatedSize != $1.item.allocatedSize {
                return $0.item.allocatedSize > $1.item.allocatedSize
            }
            return $0.item.url.path < $1.item.url.path
        }
    }

    public func resetItems(for projection: ApplicationProjection) -> [ScannedItem] {
        groupedAssociations(in: projection.associations).compactMap { group in
            let ownership = effectiveOwnership(in: group)
            let risk = effectiveRisk(in: group)
            guard ownership == .owned,
                  risk < .sensitive,
                  group.allSatisfy({ $0.association.confidence == .high }),
                  let representative = representative(in: group) else {
                return nil
            }
            return CleanupReviewItem(
                item: representative.item,
                ownership: ownership,
                evidence: representative.association.evidence,
                effectiveRisk: risk
            ).item
        }
        .sorted {
            if $0.allocatedSize != $1.allocatedSize {
                return $0.allocatedSize > $1.allocatedSize
            }
            return $0.url.path < $1.url.path
        }
    }

    private func reviewItems(
        in associations: [ApplicationAssociationProjection]
    ) -> [CleanupReviewItem] {
        groupedAssociations(in: associations).compactMap { group in
            let risk = effectiveRisk(in: group)
            guard risk != .managed,
                  let representative = representative(in: group) else {
                return nil
            }
            return CleanupReviewItem(
                item: representative.item,
                ownership: effectiveOwnership(in: group),
                evidence: representative.association.evidence,
                effectiveRisk: risk
            )
        }
    }

    private func groupedAssociations(
        in associations: [ApplicationAssociationProjection]
    ) -> [[ApplicationAssociationProjection]] {
        Array(Dictionary(grouping: associations, by: { $0.item.id }).values)
    }

    private func effectiveOwnership(
        in group: [ApplicationAssociationProjection]
    ) -> AssociationOwnership {
        if group.contains(where: { $0.association.ownership == .shared }) {
            return .shared
        }
        if group.contains(where: { $0.association.ownership == .possible }) {
            return .possible
        }
        return .owned
    }

    private func effectiveRisk(
        in group: [ApplicationAssociationProjection]
    ) -> RiskLevel {
        group.reduce(.safe) { risk, pair in
            max(risk, pair.item.risk, pair.association.risk)
        }
    }

    private func representative(
        in group: [ApplicationAssociationProjection]
    ) -> ApplicationAssociationProjection? {
        let ownership = effectiveOwnership(in: group)
        return group
            .filter { $0.association.ownership == ownership }
            .sorted {
                if $0.association.confidence != $1.association.confidence {
                    return $0.association.confidence > $1.association.confidence
                }
                if $0.association.evidence != $1.association.evidence {
                    return $0.association.evidence.rawValue
                        < $1.association.evidence.rawValue
                }
                return $0.association.id.uuidString < $1.association.id.uuidString
            }
            .first
    }
}
