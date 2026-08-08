import Foundation

/// A pure, read-only projection of AI-tool discovery results, shaped for a
/// future UI to consume directly. It performs only normalization, grouping and
/// deterministic ordering — it contains no SwiftUI, no scheduling, no
/// persistence and no write operations.
///
/// All contained values are `Sendable` and the whole projection is `Equatable`,
/// so it can be published from a MainActor model and diffed cheaply.
public struct AIManagementProjection: Sendable, Equatable {
    /// All discovered records, ordered deterministically (see `sortKey`).
    public let records: [AIToolRecord]
    /// Records grouped by kind. Each group is deterministically ordered.
    public let applications: [AIToolRecord]
    public let clis: [AIToolRecord]
    public let skills: [AIToolRecord]
    public let plugins: [AIToolRecord]
    /// Records that are attributed to a single tool.
    public let toolOwnedRecords: [AIToolRecord]
    /// Records that are shared across tools (for example, shared Skills).
    public let sharedRecords: [AIToolRecord]
    /// Every distinct coverage failure observed, with how many records carry it.
    public let coverageFailureCounts: [AIToolCoverageFailure: Int]
    /// Records that carry at least one coverage failure, for honest surfacing.
    public let recordsWithCoverageFailures: [AIToolRecord]

    public init(records: [AIToolRecord]) {
        let sorted = records.sorted(by: Self.isOrderedBefore)
        self.records = sorted
        self.applications = sorted.filter { $0.kind == .application }
        self.clis = sorted.filter { $0.kind == .cli }
        self.skills = sorted.filter { $0.kind == .skill }
        self.plugins = sorted.filter { $0.kind == .plugin }
        self.toolOwnedRecords = sorted.filter {
            if case .tool = $0.owner { return true }
            return false
        }
        self.sharedRecords = sorted.filter { $0.owner == .shared }

        var counts: [AIToolCoverageFailure: Int] = [:]
        for record in sorted {
            for failure in record.coverageFailures {
                counts[failure, default: 0] += 1
            }
        }
        self.coverageFailureCounts = counts
        self.recordsWithCoverageFailures = sorted.filter {
            !$0.coverageFailures.isEmpty
        }
    }

    /// An empty projection, used as the initial published value.
    public static let empty = AIManagementProjection(records: [])

    public var isEmpty: Bool { records.isEmpty }

    // MARK: - Deterministic ordering

    /// A total, stable ordering: by kind, then display name (case-insensitive),
    /// then the record's stable ID as a final tie-breaker so equal names never
    /// reorder between runs.
    private static func isOrderedBefore(_ lhs: AIToolRecord, _ rhs: AIToolRecord) -> Bool {
        let lhsKind = kindOrder(lhs.kind)
        let rhsKind = kindOrder(rhs.kind)
        if lhsKind != rhsKind { return lhsKind < rhsKind }
        let lhsName = lhs.displayName.lowercased()
        let rhsName = rhs.displayName.lowercased()
        if lhsName != rhsName { return lhsName < rhsName }
        return lhs.id < rhs.id
    }

    private static func kindOrder(_ kind: AIToolKind) -> Int {
        switch kind {
        case .application: return 0
        case .cli: return 1
        case .skill: return 2
        case .plugin: return 3
        }
    }
}
