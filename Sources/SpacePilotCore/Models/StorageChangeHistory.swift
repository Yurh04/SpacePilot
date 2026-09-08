import Foundation

public enum StorageChangeKind: String, Codable, CaseIterable, Sendable {
    case added
    case grown
    case deleted
}

public enum StorageChangeConfidence: String, Codable, Sendable {
    case high
    case estimated
}

public enum StorageChangeTimeRange: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30

    public var id: Self { self }

    public func cutoff(relativeTo now: Date) -> Date {
        now.addingTimeInterval(-TimeInterval(rawValue * 24 * 60 * 60))
    }
}

public enum StorageChangeKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case added
    case grown
    case deleted

    public var id: Self { self }

    public func includes(_ kind: StorageChangeKind) -> Bool {
        self == .all || rawValue == kind.rawValue
    }
}

public struct StorageChangeEntry: Identifiable, Codable, Hashable, Sendable {
    public static let individualDisplayThreshold: Int64 = 100 * 1_024 * 1_024
    public static let highlightThreshold: Int64 = 1_024 * 1_024 * 1_024

    public let id: UUID
    public let url: URL
    public let kind: StorageChangeKind
    public let beforeBytes: Int64
    public let afterBytes: Int64
    public let startedAt: Date
    public let observedAt: Date
    public let category: ItemCategory?
    public let ownerName: String?
    public let risk: RiskLevel?
    public let isAggregated: Bool
    public let confidence: StorageChangeConfidence

    public init(
        id: UUID = UUID(),
        url: URL,
        kind: StorageChangeKind,
        beforeBytes: Int64,
        afterBytes: Int64,
        startedAt: Date,
        observedAt: Date,
        category: ItemCategory? = nil,
        ownerName: String? = nil,
        risk: RiskLevel? = nil,
        isAggregated: Bool = false,
        confidence: StorageChangeConfidence = .high
    ) {
        self.id = id
        self.url = url.standardizedFileURL
        self.kind = kind
        self.beforeBytes = max(0, beforeBytes)
        self.afterBytes = max(0, afterBytes)
        self.startedAt = startedAt
        self.observedAt = observedAt
        self.category = category
        self.ownerName = ownerName
        self.risk = risk
        self.isAggregated = isAggregated
        self.confidence = confidence
    }

    public var deltaBytes: Int64 { afterBytes - beforeBytes }
    public var magnitudeBytes: Int64 { abs(deltaBytes) }
    public var isHighlighted: Bool { magnitudeBytes >= Self.highlightThreshold }
    public var isSafeToClean: Bool {
        kind != .deleted && !isAggregated && risk == .safe
    }
}

public struct StorageChangeFileState: Codable, Hashable, Sendable {
    public let url: URL
    public let allocatedSize: Int64
    public let resourceIdentifier: String?
    public let category: ItemCategory?
    public let ownerName: String?
    public let risk: RiskLevel?
    public let observedAt: Date
    public let lastEventID: Int64

    public init(
        url: URL,
        allocatedSize: Int64,
        resourceIdentifier: String?,
        category: ItemCategory? = nil,
        ownerName: String? = nil,
        risk: RiskLevel? = nil,
        observedAt: Date,
        lastEventID: Int64
    ) {
        self.url = url.standardizedFileURL
        self.allocatedSize = max(0, allocatedSize)
        self.resourceIdentifier = resourceIdentifier
        self.category = category
        self.ownerName = ownerName
        self.risk = risk
        self.observedAt = observedAt
        self.lastEventID = max(0, lastEventID)
    }
}

public struct DiskSpaceObservation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let observedAt: Date
    public let totalCapacity: Int64
    public let availableCapacity: Int64

    public init(
        id: UUID = UUID(),
        observedAt: Date,
        totalCapacity: Int64,
        availableCapacity: Int64
    ) {
        self.id = id
        self.observedAt = observedAt
        self.totalCapacity = max(0, totalCapacity)
        self.availableCapacity = max(0, availableCapacity)
    }
}

public struct StorageChangeCoverageGap: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let reason: String

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, reason: String) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reason = reason
    }
}

public struct StorageChangeHistory: Codable, Hashable, Sendable {
    public let entries: [StorageChangeEntry]
    public let observations: [DiskSpaceObservation]
    public let coverageGaps: [StorageChangeCoverageGap]
    public let baselineEstablishedAt: Date?

    public init(
        entries: [StorageChangeEntry] = [],
        observations: [DiskSpaceObservation] = [],
        coverageGaps: [StorageChangeCoverageGap] = [],
        baselineEstablishedAt: Date? = nil
    ) {
        self.entries = entries
        self.observations = observations
        self.coverageGaps = coverageGaps
        self.baselineEstablishedAt = baselineEstablishedAt
    }
}

public struct StorageChangeProjection: Sendable {
    public static let itemDisplayLimit = 100

    public let entries: [StorageChangeEntry]
    public let addedBytes: Int64
    public let grownBytes: Int64
    public let releasedBytes: Int64
    public let trackedNetBytes: Int64
    public let availableCapacityDelta: Int64?
    public let hasCoverageGap: Bool
    public let baselineEstablishedAt: Date?

    public init(
        history: StorageChangeHistory,
        timeRange: StorageChangeTimeRange,
        kindFilter: StorageChangeKindFilter,
        category: ItemCategory? = nil,
        searchText: String = "",
        safeOnly: Bool = false,
        now: Date = .now
    ) {
        let cutoff = timeRange.cutoff(relativeTo: now)
        let matching = history.entries.filter { entry in
            entry.observedAt >= cutoff
                && kindFilter.includes(entry.kind)
                && (category == nil || entry.category == category)
                && (searchText.isEmpty
                    || entry.url.path.localizedCaseInsensitiveContains(searchText)
                    || entry.ownerName?.localizedCaseInsensitiveContains(searchText) == true)
                && (!safeOnly || entry.isSafeToClean)
        }
        entries = Array(matching.sorted {
            if $0.magnitudeBytes != $1.magnitudeBytes {
                return $0.magnitudeBytes > $1.magnitudeBytes
            }
            return $0.observedAt > $1.observedAt
        }.prefix(Self.itemDisplayLimit))
        addedBytes = matching.lazy.filter { $0.kind == .added }.reduce(0) { $0 + $1.magnitudeBytes }
        grownBytes = matching.lazy.filter { $0.kind == .grown }.reduce(0) { $0 + $1.magnitudeBytes }
        releasedBytes = matching.lazy.filter { $0.kind == .deleted }.reduce(0) { $0 + $1.magnitudeBytes }
        trackedNetBytes = addedBytes + grownBytes - releasedBytes

        let observations = history.observations
            .filter { $0.observedAt >= cutoff }
            .sorted { $0.observedAt < $1.observedAt }
        if let first = observations.first, let last = observations.last, first.id != last.id {
            availableCapacityDelta = last.availableCapacity - first.availableCapacity
        } else {
            availableCapacityDelta = nil
        }
        hasCoverageGap = history.coverageGaps.contains { gap in
            gap.endedAt.map { $0 >= cutoff } ?? true
        }
        baselineEstablishedAt = history.baselineEstablishedAt
    }
}
