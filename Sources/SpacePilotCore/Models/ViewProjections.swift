import Foundation

public struct StorageCategorySummary: Identifiable, Sendable {
    public var id: ItemCategory { category }
    public let category: ItemCategory
    public let allocatedSize: Int64
    public let itemCount: Int
}

public struct OverviewProjection: Sendable {
    public let totalUsedBytes: Int64
    public let analyzedBytes: Int64
    public let reclaimableBytes: Int64
    public let preselectedRecommendations: [ScannedItem]

    public init(snapshot: ScanSnapshot) {
        if let volume = snapshot.volume {
            totalUsedBytes = max(0, volume.totalCapacity - volume.availableCapacity)
        } else {
            totalUsedBytes = snapshot.items.reduce(0) { $0 + $1.allocatedSize }
        }
        analyzedBytes = snapshot.items.reduce(0) { $0 + $1.allocatedSize }
            + snapshot.applications.reduce(0) { $0 + $1.allocatedSize }
        preselectedRecommendations = snapshot.items
            .filter { $0.risk == .safe }
            .sorted { $0.allocatedSize > $1.allocatedSize }
        reclaimableBytes = preselectedRecommendations.reduce(0) { $0 + $1.allocatedSize }
    }
}

public struct StorageProjection: Sendable {
    public let categories: [StorageCategorySummary]
    public let largestItems: [ScannedItem]
    public let oldItems: [ScannedItem]

    public init(snapshot: ScanSnapshot) {
        var categoryValues = Dictionary(grouping: snapshot.items, by: \.category)
            .map { category, items in
                StorageCategorySummary(
                    category: category,
                    allocatedSize: items.reduce(0) { $0 + $1.allocatedSize },
                    itemCount: items.count
                )
            }
        if let volume = snapshot.volume {
            let used = max(0, volume.totalCapacity - volume.availableCapacity)
            let classified = categoryValues.reduce(0) { $0 + $1.allocatedSize }
                + snapshot.applications.reduce(0) { $0 + $1.allocatedSize }
            let other = max(0, used - classified)
            if other > 0 {
                categoryValues.append(StorageCategorySummary(
                    category: .system,
                    allocatedSize: other,
                    itemCount: 0
                ))
            }
        }
        categories = categoryValues.sorted { $0.allocatedSize > $1.allocatedSize }
        largestItems = Array(snapshot.items.sorted { $0.allocatedSize > $1.allocatedSize }.prefix(100))
        let cutoff = Date.now.addingTimeInterval(-180 * 24 * 60 * 60)
        oldItems = snapshot.items
            .filter { ($0.modificationDate ?? .distantFuture) < cutoff }
            .sorted { ($0.modificationDate ?? .distantFuture) < ($1.modificationDate ?? .distantFuture) }
    }
}

public extension ItemCategory {
    var displayName: String {
        switch self {
        case .application: "Application Data"
        case .personal: "Personal Files"
        case .developer: "Developer Files"
        case .aiData: "AI Data"
        case .cache: "Caches"
        case .log: "Logs"
        case .conversation: "Conversations"
        case .model: "Models"
        case .plugin: "Plugins"
        case .skill: "Skills"
        case .system: "System"
        case .unclassified: "Unclassified"
        }
    }
}

public extension RiskLevel {
    var displayName: String {
        switch self {
        case .safe: "Safe to clean"
        case .rebuildable: "Rebuildable"
        case .sensitive: "Sensitive"
        case .managed: "Provider managed"
        }
    }
}
