public enum PluginComponentKind: String, Codable, Sendable {
    case skill
    case mcpServer
    case app
}

public struct PluginComponent: Sendable {
    public let kind: PluginComponentKind
    public let relativePath: String

    public init(kind: PluginComponentKind, relativePath: String) {
        self.kind = kind
        self.relativePath = relativePath
    }
}
