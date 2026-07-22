import Foundation

public struct ApplicationUninstallPlanner: Sendable {
    public init() {}

    public func cleanupItems(for projection: ApplicationProjection) -> [ScannedItem] {
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
        let related = uniqueItems(in: projection.associations) {
            $0.association.confidence == .high && $0.item.risk != .managed
        }
        return [appItem] + related.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    public func resetItems(for projection: ApplicationProjection) -> [ScannedItem] {
        uniqueItems(in: projection.associations) {
            $0.association.confidence == .high
                && $0.association.risk != .sensitive
                && $0.association.risk != .managed
        }
            .sorted { $0.allocatedSize > $1.allocatedSize }
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
