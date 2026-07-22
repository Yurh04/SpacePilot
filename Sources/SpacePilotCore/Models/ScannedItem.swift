import Foundation

public enum RiskLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case safe
    case rebuildable
    case sensitive
    case managed

    public static func < (lhs: Self, rhs: Self) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}

public enum ItemCategory: String, Codable, CaseIterable, Sendable {
    case application
    case personal
    case developer
    case aiData
    case cache
    case log
    case conversation
    case model
    case plugin
    case skill
    case system
    case unclassified
}

public struct ScannedItem: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let resourceIdentifier: String?
    public let category: ItemCategory
    public let risk: RiskLevel
    public let ownerID: UUID?
    public let explanation: String

    public init(
        id: UUID = UUID(),
        url: URL,
        logicalSize: Int64,
        allocatedSize: Int64,
        creationDate: Date? = nil,
        modificationDate: Date? = nil,
        resourceIdentifier: String? = nil,
        category: ItemCategory,
        risk: RiskLevel,
        ownerID: UUID? = nil,
        explanation: String
    ) {
        self.id = id
        self.url = url
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.resourceIdentifier = resourceIdentifier
        self.category = category
        self.risk = risk
        self.ownerID = ownerID
        self.explanation = explanation
    }
}
