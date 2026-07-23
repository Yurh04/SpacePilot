import Foundation

public enum CleanupItemKind: String, Codable, Sendable {
    case regularFile
    case directory
}

public enum CleanupOutcomeStatus: String, Codable, Sendable {
    case movedToTrash
    case skippedChanged
    case skippedProtected
    case failed
}

public enum CleanupOutcomeReason: String, Codable, Sendable {
    case moved
    case changedIdentity
    case missingSource
    case protectedPath
    case permissionDenied
    case moveFailed
}

public struct CleanupCandidate: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let url: URL
    public let allocatedSize: Int64
    public let risk: RiskLevel
    public let itemKind: CleanupItemKind
    public let expectedResourceIdentifier: String?
    public let expectedModificationDate: Date?
    public let explanation: String

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        url: URL,
        allocatedSize: Int64,
        risk: RiskLevel,
        itemKind: CleanupItemKind = .regularFile,
        expectedResourceIdentifier: String?,
        expectedModificationDate: Date?,
        explanation: String
    ) {
        self.id = id
        self.itemID = itemID
        self.url = url
        self.allocatedSize = allocatedSize
        self.risk = risk
        self.itemKind = itemKind
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
    public let reason: CleanupOutcomeReason?
    public let sourceURL: URL?
    public let sourceAllocatedSize: Int64?
    public let sourceExplanation: String?

    public init(
        id: UUID = UUID(),
        candidateID: UUID,
        status: CleanupOutcomeStatus,
        resultingURL: URL?,
        message: String,
        reason: CleanupOutcomeReason? = nil,
        sourceURL: URL? = nil,
        sourceAllocatedSize: Int64? = nil,
        sourceExplanation: String? = nil
    ) {
        self.id = id
        self.candidateID = candidateID
        self.status = status
        self.resultingURL = resultingURL
        self.message = message
        self.reason = reason
        self.sourceURL = sourceURL
        self.sourceAllocatedSize = sourceAllocatedSize
        self.sourceExplanation = sourceExplanation
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
