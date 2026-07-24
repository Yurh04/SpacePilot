import Foundation

public struct CodexAdapter: AIApplicationAdapting {
    private let cache: (any ScanResultCaching)?

    public init(cache: (any ScanResultCaching)? = nil) {
        self.cache = cache
    }

    public func scan(homeDirectory: URL) async throws -> AIApplicationScanResult {
        try await RuleBasedAIAdapter(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            rootRelativePath: ".codex",
            rules: [
                .init(relativePathPrefix: "sessions", category: .conversation, risk: .sensitive, explanation: "Codex conversation history"),
                .init(relativePathPrefix: "logs", category: .log, risk: .rebuildable, explanation: "Codex diagnostic logs"),
                .init(relativePathPrefix: "cache", category: .cache, risk: .safe, explanation: "Codex rebuildable cache"),
                .init(relativePathPrefix: "plugins", category: .plugin, risk: .managed, explanation: "Codex managed plugins"),
                .init(relativePathPrefix: "skills", category: .skill, risk: .managed, explanation: "Codex-specific skills"),
                .init(relativePathPrefix: "config.toml", category: .aiData, risk: .sensitive, explanation: "Codex configuration")
            ],
            cacheKey: "codex-v1",
            cache: cache
        ).scan(homeDirectory: homeDirectory)
    }
}
