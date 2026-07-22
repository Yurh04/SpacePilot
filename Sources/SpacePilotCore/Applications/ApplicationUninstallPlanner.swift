import Foundation

public struct ApplicationUninstallPlanner: Sendable {
    public init() {}

    public func cleanupItems(for application: ApplicationRecord, snapshot: ScanSnapshot) -> [ScannedItem] {
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
        let approvedIDs = Set(application.associations
            .filter { $0.confidence == .high }
            .map(\.itemID))
        let related = snapshot.items.filter { approvedIDs.contains($0.id) && $0.risk != .managed }
        return [appItem] + related.sorted { $0.allocatedSize > $1.allocatedSize }
    }

    public func resetItems(for application: ApplicationRecord, snapshot: ScanSnapshot) -> [ScannedItem] {
        let approvedIDs = Set(application.associations
            .filter { $0.confidence == .high && $0.risk != .sensitive && $0.risk != .managed }
            .map(\.itemID))
        return snapshot.items
            .filter { approvedIDs.contains($0.id) }
            .sorted { $0.allocatedSize > $1.allocatedSize }
    }
}
