import Foundation

public struct DiagnosticReport: Codable, Sendable {
    public let generatedAt: Date
    public let snapshotID: UUID?
    public let completedAt: Date?
    public let itemCount: Int
    public let applicationCount: Int
    public let aiApplicationCount: Int
    public let pluginCount: Int
    public let skillCount: Int
    public let deniedPathCount: Int
    public let cleanupTransactionCount: Int

    public init(snapshot: ScanSnapshot?, cleanupTransactionCount: Int) {
        generatedAt = .now
        snapshotID = snapshot?.id
        completedAt = snapshot?.completedAt
        itemCount = snapshot?.items.count ?? 0
        applicationCount = snapshot?.applications.count ?? 0
        aiApplicationCount = snapshot?.aiApplications.count ?? 0
        pluginCount = snapshot?.plugins.count ?? 0
        skillCount = snapshot?.skills.count ?? 0
        deniedPathCount = snapshot?.coverage.deniedPaths.count ?? 0
        self.cleanupTransactionCount = cleanupTransactionCount
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
