import Foundation

public struct ApplicationCacheGroup: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let applicationURL: URL?
    public let items: [ScannedItem]
    public let allocatedSize: Int64
    public let risk: RiskLevel

    public init(
        id: String,
        name: String,
        bundleIdentifier: String?,
        applicationURL: URL?,
        items: [ScannedItem],
        allocatedSize: Int64,
        risk: RiskLevel
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
        self.items = items
        self.allocatedSize = allocatedSize
        self.risk = risk
    }
}

public struct ApplicationCacheProjection: Sendable {
    public let groups: [ApplicationCacheGroup]
    public let totalBytes: Int64
    public let safeBytes: Int64
    public let safeItemCount: Int
    public let checkFirstItemCount: Int
    public let coverage: ScanCoverage

    public init(snapshot: ScanSnapshot) {
        self = try! Self(snapshot: snapshot, checkCancellation: {})
    }

    init(
        snapshot: ScanSnapshot,
        checkCancellation: @escaping @Sendable () throws -> Void
    ) throws {
        try checkCancellation()
        let applicationsByID = Dictionary(
            uniqueKeysWithValues: snapshot.applications.map { ($0.id, $0) }
        )
        var itemsByGroup: [String: [ScannedItem]] = [:]
        var applicationsByGroup: [String: ApplicationRecord] = [:]
        var checkpoint = ProjectionCancellationCheckpoint(
            checkCancellation: checkCancellation
        )

        var total: Int64 = 0
        var safeTotal: Int64 = 0
        var safeCount = 0
        var checkCount = 0
        for item in snapshot.items
        where item.category == .cache
            && item.cleanupPolicyScope == .applicationCache {
            try checkpoint.checkPeriodically()
            guard item.risk == .safe || item.risk == .rebuildable else { continue }
            let application = item.ownerID.flatMap { applicationsByID[$0] }
            let key = application.map { "application:\($0.id.uuidString)" }
                ?? "bundle:\(item.cleanupOwnerIdentifier ?? item.url.path)"
            itemsByGroup[key, default: []].append(item)
            if let application { applicationsByGroup[key] = application }
            total += item.allocatedSize
            if item.risk == .safe {
                safeTotal += item.allocatedSize
                safeCount += 1
            } else {
                checkCount += 1
            }
        }

        var builtGroups: [ApplicationCacheGroup] = []
        builtGroups.reserveCapacity(itemsByGroup.count)
        for (key, values) in itemsByGroup {
            try checkpoint.checkPeriodically()
            let sortedItems = values.sorted {
                if $0.allocatedSize != $1.allocatedSize {
                    return $0.allocatedSize > $1.allocatedSize
                }
                return $0.url.path < $1.url.path
            }
            guard let first = sortedItems.first else { continue }
            let application = applicationsByGroup[key]
            let identifier = application?.bundleIdentifier
                ?? first.cleanupOwnerIdentifier
            builtGroups.append(ApplicationCacheGroup(
                id: key,
                name: application?.name ?? identifier ?? first.url.lastPathComponent,
                bundleIdentifier: identifier,
                applicationURL: application?.url,
                items: sortedItems,
                allocatedSize: sortedItems.reduce(Int64(0)) {
                    $0 + $1.allocatedSize
                },
                risk: sortedItems.map(\.risk).max() ?? .safe
            ))
        }

        groups = builtGroups.sorted {
            if $0.allocatedSize != $1.allocatedSize {
                return $0.allocatedSize > $1.allocatedSize
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        totalBytes = total
        safeBytes = safeTotal
        safeItemCount = safeCount
        checkFirstItemCount = checkCount
        coverage = snapshot.coverage
        try checkCancellation()
    }
}
