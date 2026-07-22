import Foundation

public enum CleanupSummary: String, Codable, Sendable {
    case success
    case partialFailure
    case failed
}

public extension CleanupTransaction {
    var summary: CleanupSummary {
        let moved = outcomes.filter { $0.status == .movedToTrash }.count
        let unsuccessful = outcomes.count - moved
        if moved == outcomes.count, !outcomes.isEmpty { return .success }
        if moved > 0, unsuccessful > 0 { return .partialFailure }
        return .failed
    }
}

public protocol CleanupExecuting: Sendable {
    func execute(plan: CleanupPlan) async throws -> CleanupTransaction
}

public struct CleanupExecutor<Mover: TrashMoving>: CleanupExecuting {
    private let policy: PathSafetyPolicy
    private let mover: Mover
    private let store: (any SnapshotStoring)?

    public init(policy: PathSafetyPolicy, mover: Mover, store: (any SnapshotStoring)? = nil) {
        self.policy = policy
        self.mover = mover
        self.store = store
    }

    public func execute(plan: CleanupPlan) async throws -> CleanupTransaction {
        var outcomes: [CleanupOutcome] = []
        for candidate in plan.candidates {
            try Task.checkCancellation()
            let canonicalURL: URL
            do {
                canonicalURL = try policy.validate(candidate.url)
            } catch {
                outcomes.append(CleanupOutcome(
                    candidateID: candidate.id,
                    status: .skippedProtected,
                    resultingURL: nil,
                    message: error.localizedDescription
                ))
                continue
            }

            guard identityStillMatches(candidate, at: canonicalURL) else {
                outcomes.append(CleanupOutcome(
                    candidateID: candidate.id,
                    status: .skippedChanged,
                    resultingURL: nil,
                    message: "File changed after the scan and was not moved"
                ))
                continue
            }

            do {
                let destination = try mover.moveToTrash(canonicalURL)
                outcomes.append(CleanupOutcome(
                    candidateID: candidate.id,
                    status: .movedToTrash,
                    resultingURL: destination,
                    message: "Moved to Trash"
                ))
            } catch {
                outcomes.append(CleanupOutcome(
                    candidateID: candidate.id,
                    status: .failed,
                    resultingURL: nil,
                    message: error.localizedDescription
                ))
            }
        }

        let transaction = CleanupTransaction(planID: plan.id, outcomes: outcomes)
        if let store { try await store.save(transaction: transaction) }
        return transaction
    }

    private func identityStillMatches(_ candidate: CleanupCandidate, at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]) else { return false }
        if candidate.allocatedSize != Int64(values.totalFileAllocatedSize ?? 0) { return false }
        if let expected = candidate.expectedResourceIdentifier,
           expected != values.fileResourceIdentifier.map({ String(describing: $0) }) { return false }
        if let expected = candidate.expectedModificationDate {
            guard let actual = values.contentModificationDate,
                  abs(actual.timeIntervalSince(expected)) < 0.001 else { return false }
        }
        return true
    }
}
