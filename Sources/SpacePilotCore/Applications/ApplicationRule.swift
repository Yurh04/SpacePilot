import Foundation

public struct ApplicationArtifactRoot: Sendable {
    public let relativePath: String
    public let category: ItemCategory
    public let risk: RiskLevel

    public init(relativePath: String, category: ItemCategory, risk: RiskLevel) {
        self.relativePath = relativePath
        self.category = category
        self.risk = risk
    }

    public static let standard: [Self] = [
        .init(relativePath: "Library/Application Support", category: .application, risk: .rebuildable),
        .init(relativePath: "Library/Caches", category: .cache, risk: .safe),
        .init(relativePath: "Library/Preferences", category: .application, risk: .rebuildable),
        .init(relativePath: "Library/Logs", category: .log, risk: .rebuildable),
        .init(relativePath: "Library/Saved Application State", category: .application, risk: .rebuildable),
        .init(relativePath: "Library/LaunchAgents", category: .application, risk: .rebuildable),
        .init(relativePath: "Library/Containers", category: .application, risk: .sensitive),
        .init(relativePath: "Library/Group Containers", category: .application, risk: .sensitive),
        .init(relativePath: "Library/HTTPStorages", category: .application, risk: .sensitive),
        .init(relativePath: "Library/WebKit", category: .cache, risk: .rebuildable),
        .init(relativePath: "Library/Application Scripts", category: .application, risk: .sensitive),
        .init(relativePath: "Library/Application Support/CrashReporter", category: .log, risk: .rebuildable),
        .init(relativePath: "Library/Logs/DiagnosticReports", category: .log, risk: .rebuildable)
    ]
}
