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
                outcomes.append(outcome(
                    for: candidate,
                    status: .skippedProtected,
                    reason: .protectedPath,
                    message: error.localizedDescription
                ))
                continue
            }

            guard FileManager.default.fileExists(atPath: canonicalURL.path) else {
                outcomes.append(outcome(
                    for: candidate,
                    status: .skippedChanged,
                    reason: .missingSource,
                    message: "Source no longer exists"
                ))
                continue
            }

            guard identityStillMatches(candidate, at: canonicalURL) else {
                outcomes.append(outcome(
                    for: candidate,
                    status: .skippedChanged,
                    reason: .changedIdentity,
                    message: "File changed after the scan and was not moved"
                ))
                continue
            }

            do {
                let destination = try mover.moveToTrash(canonicalURL)
                outcomes.append(outcome(
                    for: candidate,
                    status: .movedToTrash,
                    reason: .moved,
                    resultingURL: destination,
                    message: "Moved to Trash"
                ))
            } catch {
                let reason: CleanupOutcomeReason = if let cocoaError = error as? CocoaError,
                                                      cocoaError.code == .fileWriteNoPermission {
                    .permissionDenied
                } else {
                    .moveFailed
                }
                outcomes.append(outcome(
                    for: candidate,
                    status: .failed,
                    reason: reason,
                    message: error.localizedDescription
                ))
            }
        }

        let transaction = CleanupTransaction(
            planID: plan.id,
            outcomes: outcomes,
            verifiedFreedBytes: CleanupVerifier().verifiedMovedBytes(plan: plan, outcomes: outcomes)
        )
        if let store { try await store.save(transaction: transaction) }
        return transaction
    }

    private func outcome(
        for candidate: CleanupCandidate,
        status: CleanupOutcomeStatus,
        reason: CleanupOutcomeReason,
        resultingURL: URL? = nil,
        message: String
    ) -> CleanupOutcome {
        CleanupOutcome(
            candidateID: candidate.id,
            status: status,
            resultingURL: resultingURL,
            message: message,
            reason: reason,
            sourceURL: candidate.url,
            sourceAllocatedSize: candidate.allocatedSize,
            sourceExplanation: candidate.explanation
        )
    }

    private func identityStillMatches(_ candidate: CleanupCandidate, at url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]) else { return false }
        let actualIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
        if let expected = candidate.expectedResourceIdentifier,
           expected != actualIdentifier { return false }

        switch candidate.itemKind {
        case .directory:
            return values.isDirectory == true
        case .regularFile:
            guard values.isRegularFile == true,
                  candidate.allocatedSize == Int64(values.totalFileAllocatedSize ?? 0)
            else { return false }
            if let expected = candidate.expectedModificationDate {
                guard let actual = values.contentModificationDate,
                      abs(actual.timeIntervalSince(expected)) < 0.001
                else { return false }
            }
            return true
        }
    }
}
