import Foundation

public enum ScanStage: String, Codable, CaseIterable, Sendable {
    case quickInventory
    case targetedAnalysis
    case indexing
    case completed
}

public struct ScanEvent: Sendable {
    public let stage: ScanStage
    public let progress: Double
    public let message: String
    public let snapshot: ScanSnapshot?

    public init(stage: ScanStage, progress: Double, message: String, snapshot: ScanSnapshot? = nil) {
        self.stage = stage
        self.progress = min(max(progress, 0), 1)
        self.message = message
        self.snapshot = snapshot
    }
}
