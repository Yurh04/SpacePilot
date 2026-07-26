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

enum ProjectionCancellationAwareOrdering {
    static func sorted<Element>(
        _ elements: [Element],
        by areInIncreasingOrder: (Element, Element) -> Bool,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws -> [Element] {
        try checkCancellation()
        guard elements.count > 1 else {
            try checkCancellation()
            return elements
        }

        var source = elements
        var width = 1
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        while width < source.count {
            var destination: [Element] = []
            destination.reserveCapacity(source.count)
            var lowerBound = 0
            while lowerBound < source.count {
                let middle = min(lowerBound + width, source.count)
                let upperBound = min(middle + width, source.count)
                var left = lowerBound
                var right = middle

                while left < middle, right < upperBound {
                    try checkpoint.checkPeriodically()
                    if areInIncreasingOrder(source[right], source[left]) {
                        destination.append(source[right])
                        right += 1
                    } else {
                        destination.append(source[left])
                        left += 1
                    }
                }
                while left < middle {
                    try checkpoint.checkPeriodically()
                    destination.append(source[left])
                    left += 1
                }
                while right < upperBound {
                    try checkpoint.checkPeriodically()
                    destination.append(source[right])
                    right += 1
                }
                lowerBound = upperBound
            }
            source = destination
            width = width > source.count / 2 ? source.count : width * 2
            try checkCancellation()
        }
        try checkCancellation()
        return source
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
    public let totalCapacityBytes: Int64
    public let totalUsedBytes: Int64
    public let availableBytes: Int64
    public let hasWholeDiskCapacity: Bool
    public let analyzedBytes: Int64
    public let reclaimableBytes: Int64
    public let categories: [StorageCategorySummary]
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
        try checkCancellation()
        let usesAggregates = snapshot.categoryAggregates != nil
        var itemBytes: Int64 = 0
        var safeItemBytes: Int64 = 0
        var categoryTotals: [ItemCategory: StorageCategoryAccumulator] = [:]
        if let aggregates = snapshot.categoryAggregates {
            for aggregate in aggregates {
                categoryTotals[aggregate.category] = StorageCategoryAccumulator(
                    allocatedSize: aggregate.allocatedSize,
                    itemCount: aggregate.itemCount
                )
                itemBytes += aggregate.allocatedSize
            }
        }
        var checkpoint = ProjectionCancellationCheckpoint(checkCancellation: checkCancellation)
        var recommendationSelection = BoundedScannedItemSelection(
            limit: Self.recommendationDisplayLimit,
            prefers: { $0.allocatedSize > $1.allocatedSize }
        )
        for item in snapshot.items {
            try checkpoint.checkPeriodically()
            if !usesAggregates {
                itemBytes += item.allocatedSize
                categoryTotals[item.category, default: .init()].add(item.allocatedSize)
            }
            if item.risk == .safe {
                safeItemBytes += item.allocatedSize
                recommendationSelection.insert(item)
            }
        }

        var applicationBytes: Int64 = 0
        for application in snapshot.applications {
            try checkpoint.checkPeriodically()
            applicationBytes += application.allocatedSize
        }
        analyzedBytes = itemBytes + applicationBytes
        if let volume = snapshot.volume,
           volume.totalCapacity > 0,
           (0...volume.totalCapacity).contains(volume.availableCapacity) {
            hasWholeDiskCapacity = true
            totalCapacityBytes = volume.totalCapacity
            totalUsedBytes = max(0, volume.totalCapacity - volume.availableCapacity)
            availableBytes = volume.availableCapacity
        } else {
            hasWholeDiskCapacity = false
            totalCapacityBytes = analyzedBytes
            totalUsedBytes = analyzedBytes
            availableBytes = 0
        }
        reclaimableBytes = safeItemBytes
        var categoryValues: [StorageCategorySummary] = []
        categoryValues.reserveCapacity(ItemCategory.allCases.count)
        for (category, total) in categoryTotals {
            try checkpoint.checkPeriodically()
            guard total.allocatedSize > 0 else { continue }
            categoryValues.append(StorageCategorySummary(
                category: category,
                allocatedSize: total.allocatedSize,
                itemCount: total.itemCount
            ))
        }
        let categoryOrder = Dictionary(
            uniqueKeysWithValues: ItemCategory.allCases.enumerated().map { ($1, $0) }
        )
        categories = try ProjectionCancellationAwareOrdering.sorted(
            categoryValues,
            by: { lhs, rhs in
                if lhs.allocatedSize != rhs.allocatedSize {
                    return lhs.allocatedSize > rhs.allocatedSize
                }
                return categoryOrder[lhs.category, default: .max]
                    < categoryOrder[rhs.category, default: .max]
            },
            checkCancellation: checkCancellation
        )
        // The heap is strictly bounded by recommendationDisplayLimit (8).
        recommendations = recommendationSelection.sortedItems
        coverage = snapshot.coverage
        try checkCancellation()
    }
}

public struct StorageProjection: Sendable {
    public static let itemDisplayLimit = 100
    public let totalCapacity: Int64
    public let usedBytes: Int64
    public let availableBytes: Int64
    public let analyzedBytes: Int64
    public let categories: [StorageCategorySummary]
    public let largestItems: [ScannedItem]
    public let oldItems: [ScannedItem]
    public let largestItemsByCategory: [ItemCategory: [ScannedItem]]
    public let oldItemsByCategory: [ItemCategory: [ScannedItem]]

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        try checkCancellation()
        let usesAggregates = snapshot.categoryAggregates != nil
        var categoryTotals: [ItemCategory: StorageCategoryAccumulator] = [:]
        if let aggregates = snapshot.categoryAggregates {
            for aggregate in aggregates {
                categoryTotals[aggregate.category] = StorageCategoryAccumulator(
                    allocatedSize: aggregate.allocatedSize,
                    itemCount: aggregate.itemCount
                )
            }
        }
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
        var largestCategorySelections: [ItemCategory: BoundedScannedItemSelection] = [:]
        var oldestCategorySelections: [ItemCategory: BoundedScannedItemSelection] = [:]
        for category in ItemCategory.allCases {
            largestCategorySelections[category] = BoundedScannedItemSelection(
                limit: Self.itemDisplayLimit,
                prefers: { $0.allocatedSize > $1.allocatedSize }
            )
            oldestCategorySelections[category] = BoundedScannedItemSelection(
                limit: Self.itemDisplayLimit,
                prefers: {
                    ($0.modificationDate ?? .distantFuture)
                        < ($1.modificationDate ?? .distantFuture)
                }
            )
        }
        var itemBytes: Int64 = snapshot.categoryAggregates?.reduce(Int64(0)) {
            $0 + $1.allocatedSize
        } ?? 0

        for item in snapshot.items {
            try checkpoint.checkPeriodically()
            if !usesAggregates {
                itemBytes += item.allocatedSize
                categoryTotals[item.category, default: .init()].add(item.allocatedSize)
            }
            largestSelection.insert(item)
            largestCategorySelections[item.category]?.insert(item)
            if (item.modificationDate ?? .distantFuture) < cutoff {
                oldestSelection.insert(item)
                oldestCategorySelections[item.category]?.insert(item)
            }
        }

        var applicationBytes: Int64 = 0
        for application in snapshot.applications {
            try checkpoint.checkPeriodically()
            applicationBytes += application.allocatedSize
        }
        analyzedBytes = itemBytes + applicationBytes
        if let volume = snapshot.volume {
            totalCapacity = volume.totalCapacity
            availableBytes = volume.availableCapacity
            usedBytes = max(0, volume.totalCapacity - volume.availableCapacity)
        } else {
            totalCapacity = analyzedBytes
            usedBytes = analyzedBytes
            availableBytes = 0
        }

        if let volume = snapshot.volume {
            let used = max(0, volume.totalCapacity - volume.availableCapacity)
            var classified: Int64 = 0
            // categoryTotals is strictly bounded by ItemCategory.allCases (12).
            for total in categoryTotals.values {
                classified += total.allocatedSize
            }
            classified += applicationBytes
            let other = max(0, used - classified)
            if other > 0 {
                categoryTotals[.system, default: .init()].allocatedSize += other
            }
        }
        var categoryValues: [StorageCategorySummary] = []
        categoryValues.reserveCapacity(ItemCategory.allCases.count)
        for (category, total) in categoryTotals {
            try checkpoint.checkPeriodically()
            guard total.allocatedSize > 0 else { continue }
            categoryValues.append(StorageCategorySummary(
                category: category,
                allocatedSize: total.allocatedSize,
                itemCount: total.itemCount
            ))
        }
        categories = try ProjectionCancellationAwareOrdering.sorted(
            categoryValues,
            by: { $0.allocatedSize > $1.allocatedSize },
            checkCancellation: checkCancellation
        )
        // Both heaps are strictly bounded by itemDisplayLimit (100).
        largestItems = largestSelection.sortedItems
        oldItems = oldestSelection.sortedItems
        largestItemsByCategory = largestCategorySelections.mapValues(\.sortedItems)
        oldItemsByCategory = oldestCategorySelections.mapValues(\.sortedItems)
        try checkCancellation()
    }

    public func items(category: ItemCategory?, oldOnly: Bool) -> [ScannedItem] {
        guard let category else {
            return oldOnly ? oldItems : largestItems
        }
        return oldOnly
            ? oldItemsByCategory[category, default: []]
            : largestItemsByCategory[category, default: []]
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
    public var ownership: AssociationOwnership { association.ownership }
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
        try checkCancellation()
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
            var relatedSize = relatedSizes[application.id, default: 0]
            var additionallyCountedItemIDs: Set<UUID> = []
            for association in application.associations {
                try checkpoint.checkPeriodically()
                guard let item = associatedItemsByID[association.itemID],
                      item.ownerID != application.id,
                      additionallyCountedItemIDs.insert(item.id).inserted
                else {
                    continue
                }
                relatedSize += item.allocatedSize
            }
            let totalSize = application.allocatedSize + relatedSize
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
            associations = try ProjectionCancellationAwareOrdering.sorted(
                associations,
                by: { $0.association.confidence > $1.association.confidence },
                checkCancellation: checkCancellation
            )
            applicationProjections.append(ApplicationProjection(
                application: application,
                totalSize: totalSize,
                associations: associations
            ))
        }

        totalSizes = allTotalSizes
        applications = try ProjectionCancellationAwareOrdering.sorted(
            applicationProjections,
            by: { $0.totalSize > $1.totalSize },
            checkCancellation: checkCancellation
        )
        try checkCancellation()
    }

    public func filtered(by searchText: String) -> [ApplicationProjection] {
        guard !searchText.isEmpty else { return applications }
        return applications.filter { $0.application.name.localizedCaseInsensitiveContains(searchText) }
    }

    public func totalSize(for applicationID: UUID) -> Int64 {
        totalSizes[applicationID, default: 0]
    }
}
