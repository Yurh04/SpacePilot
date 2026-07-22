import Foundation

public struct StorageCategorySummary: Identifiable, Sendable {
    public var id: ItemCategory { category }
    public let category: ItemCategory
    public let allocatedSize: Int64
    public let itemCount: Int
}

public struct OverviewProjection: Sendable {
    public static let recommendationDisplayLimit = 8
    public let totalUsedBytes: Int64
    public let analyzedBytes: Int64
    public let reclaimableBytes: Int64
    public let recommendations: [ScannedItem]

    public var preselectedRecommendations: [ScannedItem] { recommendations }

    public init(snapshot: ScanSnapshot) {
        var itemBytes: Int64 = 0
        var safeItemBytes: Int64 = 0
        var recommendationSelection = BoundedScannedItemSelection(
            limit: Self.recommendationDisplayLimit,
            prefers: { $0.allocatedSize > $1.allocatedSize }
        )
        for item in snapshot.items {
            itemBytes += item.allocatedSize
            if item.risk == .safe {
                safeItemBytes += item.allocatedSize
                recommendationSelection.insert(item)
            }
        }

        if let volume = snapshot.volume {
            totalUsedBytes = max(0, volume.totalCapacity - volume.availableCapacity)
        } else {
            totalUsedBytes = itemBytes
        }
        analyzedBytes = itemBytes
            + snapshot.applications.reduce(0) { $0 + $1.allocatedSize }
        reclaimableBytes = safeItemBytes
        recommendations = recommendationSelection.sortedItems
    }
}

public struct StorageProjection: Sendable {
    public static let itemDisplayLimit = 100
    public let categories: [StorageCategorySummary]
    public let largestItems: [ScannedItem]
    public let oldItems: [ScannedItem]

    public init(snapshot: ScanSnapshot) {
        var categoryTotals: [ItemCategory: StorageCategoryAccumulator] = [:]
        var largestSelection = BoundedScannedItemSelection(
            limit: Self.itemDisplayLimit,
            prefers: { $0.allocatedSize > $1.allocatedSize }
        )
        let cutoff = Date.now.addingTimeInterval(-180 * 24 * 60 * 60)
        var oldestSelection = BoundedScannedItemSelection(
            limit: Self.itemDisplayLimit,
            prefers: { ($0.modificationDate ?? .distantFuture) < ($1.modificationDate ?? .distantFuture) }
        )

        for item in snapshot.items {
            categoryTotals[item.category, default: .init()].add(item.allocatedSize)
            largestSelection.insert(item)
            if (item.modificationDate ?? .distantFuture) < cutoff {
                oldestSelection.insert(item)
            }
        }

        var categoryValues = categoryTotals.map { category, total in
            StorageCategorySummary(
                category: category,
                allocatedSize: total.allocatedSize,
                itemCount: total.itemCount
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
        largestItems = largestSelection.sortedItems
        oldItems = oldestSelection.sortedItems
    }
}

private struct StorageCategoryAccumulator {
    var allocatedSize: Int64 = 0
    var itemCount = 0

    mutating func add(_ size: Int64) {
        allocatedSize += size
        itemCount += 1
    }
}

private struct BoundedScannedItemSelection {
    let limit: Int
    let prefers: (ScannedItem, ScannedItem) -> Bool
    private var heap: [ScannedItem] = []

    init(limit: Int, prefers: @escaping (ScannedItem, ScannedItem) -> Bool) {
        self.limit = limit
        self.prefers = prefers
    }

    var sortedItems: [ScannedItem] {
        heap.sorted(by: prefers)
    }

    mutating func insert(_ item: ScannedItem) {
        guard limit > 0 else { return }
        if heap.count < limit {
            heap.append(item)
            siftUp(from: heap.count - 1)
        } else if prefers(item, heap[0]) {
            heap[0] = item
            siftDown(from: 0)
        }
    }

    private func isWorse(_ lhs: ScannedItem, than rhs: ScannedItem) -> Bool {
        prefers(rhs, lhs)
    }

    private mutating func siftUp(from startIndex: Int) {
        var child = startIndex
        while child > 0 {
            let parent = (child - 1) / 2
            guard isWorse(heap[child], than: heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from startIndex: Int) {
        var parent = startIndex
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worseChild = left
            if right < heap.count, isWorse(heap[right], than: heap[left]) {
                worseChild = right
            }
            guard isWorse(heap[worseChild], than: heap[parent]) else { return }
            heap.swapAt(parent, worseChild)
            parent = worseChild
        }
    }
}

public struct ApplicationListProjection: Sendable {
    public let applications: [ApplicationRecord]
    private let totalSizes: [UUID: Int64]

    public init(snapshot: ScanSnapshot, searchText _: String) {
        let relatedSizes = snapshot.items.reduce(into: [UUID: Int64]()) { sizes, item in
            guard let ownerID = item.ownerID else { return }
            sizes[ownerID, default: 0] += item.allocatedSize
        }
        let allTotalSizes = snapshot.applications.reduce(into: [UUID: Int64]()) { sizes, application in
            sizes[application.id] = application.allocatedSize + relatedSizes[application.id, default: 0]
        }
        totalSizes = allTotalSizes
        applications = snapshot.applications
            .sorted { allTotalSizes[$0.id, default: 0] > allTotalSizes[$1.id, default: 0] }
    }

    public func filtered(by searchText: String) -> [ApplicationRecord] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    public func totalSize(for applicationID: UUID) -> Int64 {
        totalSizes[applicationID, default: 0]
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
