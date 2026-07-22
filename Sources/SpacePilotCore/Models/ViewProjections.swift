import Foundation

struct ProjectionCancellationCheckpoint {
    private static let interval = 1_024

    private var iteration = 0
    private let checkCancellation: @Sendable () throws -> Void

    init(checkCancellation: @escaping @Sendable () throws -> Void) {
        self.checkCancellation = checkCancellation
    }

    mutating func checkPeriodically() throws {
        iteration &+= 1
        if iteration == 1 || iteration.isMultiple(of: Self.interval) {
            try checkCancellation()
        }
    }
}

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
    public let coverage: ScanCoverage

    public var preselectedRecommendations: [ScannedItem] { recommendations }

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        var itemBytes: Int64 = 0
        var safeItemBytes: Int64 = 0
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var recommendationSelection = BoundedScannedItemSelection(
            limit: Self.recommendationDisplayLimit,
            prefers: { $0.allocatedSize > $1.allocatedSize }
        )
        for item in snapshot.items {
            try checkpoint.checkPeriodically()
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
        coverage = snapshot.coverage
    }
}

public struct StorageProjection: Sendable {
    public static let itemDisplayLimit = 100
    public let categories: [StorageCategorySummary]
    public let largestItems: [ScannedItem]
    public let oldItems: [ScannedItem]

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        var categoryTotals: [ItemCategory: StorageCategoryAccumulator] = [:]
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
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
            try checkpoint.checkPeriodically()
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

public struct ApplicationAssociationProjection: Identifiable, Sendable {
    public var id: UUID { association.id }
    public let association: ArtifactAssociation
    public let item: ScannedItem
}

public struct ApplicationProjection: Identifiable, Sendable {
    public var id: UUID { application.id }
    public let application: ApplicationRecord
    public let totalSize: Int64
    public let associations: [ApplicationAssociationProjection]
}

public struct ApplicationListProjection: Sendable {
    public let applications: [ApplicationProjection]
    private let totalSizes: [UUID: Int64]

    public init(snapshot: ScanSnapshot, searchText _: String) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var associatedItemIDs: Set<UUID> = []
        for application in snapshot.applications {
            try checkpoint.checkPeriodically()
            for association in application.associations {
                try checkpoint.checkPeriodically()
                associatedItemIDs.insert(association.itemID)
            }
        }

        var relatedSizes: [UUID: Int64] = [:]
        var associatedItemsByID: [UUID: ScannedItem] = [:]
        for item in snapshot.items {
            try checkpoint.checkPeriodically()
            if let ownerID = item.ownerID {
                relatedSizes[ownerID, default: 0] += item.allocatedSize
            }
            if associatedItemIDs.contains(item.id) {
                associatedItemsByID[item.id] = item
            }
        }

        var allTotalSizes: [UUID: Int64] = [:]
        var applicationProjections: [ApplicationProjection] = []
        applicationProjections.reserveCapacity(snapshot.applications.count)
        for application in snapshot.applications {
            try checkpoint.checkPeriodically()
            let totalSize = application.allocatedSize + relatedSizes[application.id, default: 0]
            allTotalSizes[application.id] = totalSize
            var associations: [ApplicationAssociationProjection] = []
            associations.reserveCapacity(application.associations.count)
            for association in application.associations {
                try checkpoint.checkPeriodically()
                if let item = associatedItemsByID[association.itemID] {
                    associations.append(ApplicationAssociationProjection(
                        association: association,
                        item: item
                    ))
                }
            }
            associations.sort { $0.association.confidence > $1.association.confidence }
            applicationProjections.append(ApplicationProjection(
                application: application,
                totalSize: totalSize,
                associations: associations
            ))
        }

        totalSizes = allTotalSizes
        applications = applicationProjections.sorted { $0.totalSize > $1.totalSize }
    }

    public func filtered(by searchText: String) -> [ApplicationProjection] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter { $0.application.name.localizedCaseInsensitiveContains(searchText) }
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
