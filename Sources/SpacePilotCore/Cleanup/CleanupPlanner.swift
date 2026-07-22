import Foundation

public enum CleanupPlanningError: Error, Equatable, LocalizedError, Sendable {
    case unknownSelection(UUID)
    case managedItem(URL)
    case sensitiveConfirmationRequired(URL)

    public var errorDescription: String? {
        switch self {
        case .unknownSelection(let id): "Selected item was not found: \(id)"
        case .managedItem(let url): "This item is managed by its provider: \(url.path)"
        case .sensitiveConfirmationRequired(let url): "Sensitive item needs separate confirmation: \(url.path)"
        }
    }
}

public struct CleanupPlanner: Sendable {
    public let policy: PathSafetyPolicy

    public init(policy: PathSafetyPolicy) {
        self.policy = policy
    }

    public func makePlan(
        snapshotID: UUID,
        items: [ScannedItem],
        selectedIDs: Set<UUID>,
        separatelyConfirmedSensitiveIDs: Set<UUID>
    ) throws -> CleanupPlan {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var candidates: [CleanupCandidate] = []

        for id in selectedIDs {
            guard let item = byID[id] else {
                throw CleanupPlanningError.unknownSelection(id)
            }
            if item.risk == .managed {
                throw CleanupPlanningError.managedItem(item.url)
            }
            if item.risk == .sensitive, !separatelyConfirmedSensitiveIDs.contains(id) {
                throw CleanupPlanningError.sensitiveConfirmationRequired(item.url)
            }

            let canonicalURL = try policy.validate(item.url)
            candidates.append(CleanupCandidate(
                itemID: item.id,
                url: canonicalURL,
                allocatedSize: item.allocatedSize,
                risk: item.risk,
                expectedResourceIdentifier: item.resourceIdentifier,
                expectedModificationDate: item.modificationDate,
                explanation: item.explanation
            ))
        }

        return CleanupPlan(
            snapshotID: snapshotID,
            candidates: candidates.sorted { $0.url.path < $1.url.path }
        )
    }
}
