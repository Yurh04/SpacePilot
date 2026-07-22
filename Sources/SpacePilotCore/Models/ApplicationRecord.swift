import Foundation

public enum AssociationEvidence: String, Codable, Sendable {
    case exactBundleIdentifier
    case exactContainerIdentifier
    case knownRule
    case signedHelperRelationship
    case vendorAndNameMatch
}

public enum AssociationConfidence: Int, Codable, Comparable, Sendable {
    case low = 20
    case medium = 60
    case high = 90

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct ArtifactAssociation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let applicationID: UUID
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let risk: RiskLevel

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        applicationID: UUID,
        evidence: AssociationEvidence,
        confidence: AssociationConfidence,
        risk: RiskLevel
    ) {
        self.id = id
        self.itemID = itemID
        self.applicationID = applicationID
        self.evidence = evidence
        self.confidence = confidence
        self.risk = risk
    }
}

public struct ApplicationRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String?
    public let version: String?
    public let url: URL
    public let executableURL: URL?
    public let allocatedSize: Int64
    public let lastUsedDate: Date?
    public let associations: [ArtifactAssociation]

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String?,
        version: String?,
        url: URL,
        executableURL: URL?,
        allocatedSize: Int64,
        lastUsedDate: Date? = nil,
        associations: [ArtifactAssociation] = []
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.url = url
        self.executableURL = executableURL
        self.allocatedSize = allocatedSize
        self.lastUsedDate = lastUsedDate
        self.associations = associations
    }
}
