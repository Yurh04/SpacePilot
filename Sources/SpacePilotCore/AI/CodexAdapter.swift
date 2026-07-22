import Foundation

public struct CodexAdapter: AIApplicationAdapting {
    public init() {}

    public func scan(homeDirectory: URL) async throws -> AIApplicationScanResult {
        try await RuleBasedAIAdapter(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            rootRelativePath: ".codex",
            rules: [
                .init(relativePathPrefix: "sessions", category: .conversation, risk: .sensitive, explanation: "Codex conversation history"),
                .init(relativePathPrefix: "logs", category: .log, risk: .rebuildable, explanation: "Codex diagnostic logs"),
                .init(relativePathPrefix: "cache", category: .cache, risk: .safe, explanation: "Codex rebuildable cache"),
                .init(relativePathPrefix: "config.toml", category: .aiData, risk: .sensitive, explanation: "Codex configuration")
            ]
        ).scan(homeDirectory: homeDirectory)
    }
}
