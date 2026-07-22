import Foundation

public struct CleanupVerification: Sendable {
    public let transaction: CleanupTransaction
    public let verifiedFreedBytes: Int64
}

public struct CleanupVerifier: Sendable {
    public init() {}

    public func verify(
        transaction: CleanupTransaction,
        beforeAvailableCapacity: Int64,
        volumeRoot: URL = URL(fileURLWithPath: "/", isDirectory: true)
    ) throws -> CleanupVerification {
        let after = try VolumeScanner(root: volumeRoot).scan().availableCapacity
        return CleanupVerification(
            transaction: transaction,
            verifiedFreedBytes: max(0, after - beforeAvailableCapacity)
        )
    }

    public func verifiedMovedBytes(plan: CleanupPlan, outcomes: [CleanupOutcome]) -> Int64 {
        let movedCandidateIDs = Set(outcomes
            .filter { $0.status == .movedToTrash }
            .map(\.candidateID))
        return plan.candidates
            .filter {
                movedCandidateIDs.contains($0.id)
                    && !FileManager.default.fileExists(atPath: $0.url.path)
            }
            .reduce(0) { $0 + $1.allocatedSize }
    }
}
