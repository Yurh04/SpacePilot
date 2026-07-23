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

public enum AssociationOwnership: String, Codable, Sendable {
    case owned
    case shared
    case possible
}

public struct ArtifactAssociation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let itemID: UUID
    public let applicationID: UUID
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let risk: RiskLevel
    public let ownership: AssociationOwnership

    public init(
        id: UUID = UUID(),
        itemID: UUID,
        applicationID: UUID,
        evidence: AssociationEvidence,
        confidence: AssociationConfidence,
        risk: RiskLevel,
        ownership: AssociationOwnership
    ) {
        self.id = id
        self.itemID = itemID
        self.applicationID = applicationID
        self.evidence = evidence
        self.confidence = confidence
        self.risk = risk
        self.ownership = ownership
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case itemID
        case applicationID
        case evidence
        case confidence
        case risk
        case ownership
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        itemID = try container.decode(UUID.self, forKey: .itemID)
        applicationID = try container.decode(UUID.self, forKey: .applicationID)
        evidence = try container.decode(AssociationEvidence.self, forKey: .evidence)
        confidence = try container.decode(AssociationConfidence.self, forKey: .confidence)
        risk = try container.decode(RiskLevel.self, forKey: .risk)
        ownership = try container.decodeIfPresent(
            AssociationOwnership.self,
            forKey: .ownership
        ) ?? .possible
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(applicationID, forKey: .applicationID)
        try container.encode(evidence, forKey: .evidence)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(risk, forKey: .risk)
        try container.encode(ownership, forKey: .ownership)
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
