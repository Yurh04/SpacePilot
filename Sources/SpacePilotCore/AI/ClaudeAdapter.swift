import Foundation

public struct ClaudeAdapter: AIApplicationAdapting {
    private let cache: (any ScanResultCaching)?

    public init(cache: (any ScanResultCaching)? = nil) {
        self.cache = cache
    }

    public func scan(homeDirectory: URL) async throws -> AIApplicationScanResult {
        try await RuleBasedAIAdapter(
            name: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            rootRelativePath: ".claude",
            rules: [
                .init(relativePathPrefix: "projects", category: .conversation, risk: .sensitive, explanation: "Claude project conversation data"),
                .init(relativePathPrefix: "debug", category: .log, risk: .rebuildable, explanation: "Claude diagnostic logs"),
                .init(relativePathPrefix: "cache", category: .cache, risk: .safe, explanation: "Claude rebuildable cache"),
                .init(relativePathPrefix: "skills", category: .skill, risk: .managed, explanation: "Claude-specific skills"),
                .init(relativePathPrefix: "settings.json", category: .aiData, risk: .sensitive, explanation: "Claude settings")
            ],
            cacheKey: "claude-v1",
            cache: cache
        ).scan(homeDirectory: homeDirectory)
    }
}
