import Foundation

public enum CleanupOutcomeStatus: String, Codable, Sendable {
    case movedToTrash
    case skippedChanged
    case skippedProtected
    case failed
}

public struct CleanupCandidate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let url: URL
    public let allocatedSize: Int64
    public let risk: RiskLevel
    public let expectedResourceIdentifier: String?
    public let expectedModificationDate: Date?
    public let explanation: String

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        url: URL,
        allocatedSize: Int64,
        risk: RiskLevel,
        expectedResourceIdentifier: String?,
        expectedModificationDate: Date?,
        explanation: String
    ) {
        self.id = id
        self.itemID = itemID
        self.url = url
        self.allocatedSize = allocatedSize
        self.risk = risk
        self.expectedResourceIdentifier = expectedResourceIdentifier
        self.expectedModificationDate = expectedModificationDate
        self.explanation = explanation
    }
}

public struct CleanupPlan: Identifiable, Codable, Sendable {
    public let id: UUID
    public let snapshotID: UUID
    public let createdAt: Date
    public let candidates: [CleanupCandidate]

    public init(id: UUID = UUID(), snapshotID: UUID, createdAt: Date = .now, candidates: [CleanupCandidate]) {
        self.id = id
        self.snapshotID = snapshotID
        self.createdAt = createdAt
        self.candidates = candidates
    }
}

public struct CleanupOutcome: Identifiable, Codable, Sendable {
    public let id: UUID
    public let candidateID: UUID
    public let status: CleanupOutcomeStatus
    public let resultingURL: URL?
    public let message: String

    public init(id: UUID = UUID(), candidateID: UUID, status: CleanupOutcomeStatus, resultingURL: URL?, message: String) {
        self.id = id
        self.candidateID = candidateID
        self.status = status
        self.resultingURL = resultingURL
        self.message = message
    }
}

public struct CleanupTransaction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let planID: UUID
    public let completedAt: Date
    public let outcomes: [CleanupOutcome]
    public let verifiedFreedBytes: Int64?

    public init(id: UUID = UUID(), planID: UUID, completedAt: Date = .now, outcomes: [CleanupOutcome], verifiedFreedBytes: Int64? = nil) {
        self.id = id
        self.planID = planID
        self.completedAt = completedAt
        self.outcomes = outcomes
        self.verifiedFreedBytes = verifiedFreedBytes
    }
}
