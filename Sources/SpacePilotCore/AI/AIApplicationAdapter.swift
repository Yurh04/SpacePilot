import Foundation

public struct AIAssetRule: Sendable {
    public let relativePathPrefix: String
    public let category: ItemCategory
    public let risk: RiskLevel
    public let explanation: String

    public init(
        relativePathPrefix: String,
        category: ItemCategory,
        risk: RiskLevel,
        explanation: String
    ) {
        self.relativePathPrefix = relativePathPrefix
        self.category = category
        self.risk = risk
        self.explanation = explanation
    }
}

public struct AIApplicationScanResult: Codable, Sendable {
    public let application: AIApplicationRecord
    public let items: [ScannedItem]
    public let cleanupRecommendedItemIDs: Set<UUID>
    public let indexedContentBodies: [String]

    public var itemsByCategory: [ItemCategory: [ScannedItem]] {
        Dictionary(grouping: items, by: \.category)
    }

    public init(
        application: AIApplicationRecord,
        items: [ScannedItem],
        cleanupRecommendedItemIDs: Set<UUID> = [],
        indexedContentBodies: [String] = []
    ) {
        self.application = application
        self.items = items
        self.cleanupRecommendedItemIDs = cleanupRecommendedItemIDs
        self.indexedContentBodies = indexedContentBodies
    }
}

public protocol AIApplicationAdapting: Sendable {
    func scan(homeDirectory: URL) async throws -> AIApplicationScanResult
}
