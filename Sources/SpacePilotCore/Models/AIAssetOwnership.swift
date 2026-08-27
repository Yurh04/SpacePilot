import Foundation
import CryptoKit

public enum AIAssetOwner: Hashable, Sendable {
    case tool(definitionID: String)
    case shared
    case plugin(pluginID: String)
    case unknown
}

extension AIAssetOwner: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case definitionID
        case pluginID
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "tool":
            let definitionID = try container.decode(String.self, forKey: .definitionID)
            self = .tool(definitionID: definitionID)
        case "shared":
            self = .shared
        case "plugin":
            let pluginID = try container.decode(String.self, forKey: .pluginID)
            self = .plugin(pluginID: pluginID)
        case "unknown":
            self = .unknown
        default:
            self = .unknown
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tool(let definitionID):
            try container.encode("tool", forKey: .kind)
            try container.encode(definitionID, forKey: .definitionID)
        case .shared:
            try container.encode("shared", forKey: .kind)
        case .plugin(let pluginID):
            try container.encode("plugin", forKey: .kind)
            try container.encode(pluginID, forKey: .pluginID)
        case .unknown:
            try container.encode("unknown", forKey: .kind)
        }
    }
}

public struct AIProjectIdentity: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let canonicalRootURL: URL

    public init(displayName: String, canonicalRootURL: URL) {
        let canonicalRootURL = canonicalRootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.id = Self.stableID(for: canonicalRootURL)
        self.displayName = displayName
        self.canonicalRootURL = canonicalRootURL
    }

    public static func stableID(for canonicalRootURL: URL) -> String {
        let path = canonicalRootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8))
        return "project:" + digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension AIProjectIdentity: Codable {
    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case canonicalRootURL
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let displayName = try container.decode(String.self, forKey: .displayName)
        let canonicalRootURL = try container.decode(URL.self, forKey: .canonicalRootURL)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let stableID = Self.stableID(for: canonicalRootURL)
        guard id == stableID else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "AIProjectIdentity id does not match canonicalRootURL"
            )
        }
        self.id = id
        self.displayName = displayName
        self.canonicalRootURL = canonicalRootURL
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(canonicalRootURL, forKey: .canonicalRootURL)
    }
}

public enum AIAssetLocationScope: Hashable, Sendable {
    case userGlobal
    case project(AIProjectIdentity)
    case system
    case bundled
}

extension AIAssetLocationScope: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case project
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "userGlobal":
            self = .userGlobal
        case "project":
            self = .project(try container.decode(AIProjectIdentity.self, forKey: .project))
        case "system":
            self = .system
        case "bundled":
            self = .bundled
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: container,
                debugDescription: "Unknown AI asset location scope: \(kind)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .userGlobal:
            try container.encode("userGlobal", forKey: .kind)
        case .project(let project):
            try container.encode("project", forKey: .kind)
            try container.encode(project, forKey: .project)
        case .system:
            try container.encode("system", forKey: .kind)
        case .bundled:
            try container.encode("bundled", forKey: .kind)
        }
    }
}

public extension AIAssetOwner {
    static func migrated(from scope: SkillScope) -> AIAssetOwner {
        switch scope {
        case .sharedAgents:
            return .shared
        case .agentSpecific(let agent):
            return .tool(definitionID: normalizedDefinitionID(fromLegacyAgent: agent))
        case .pluginProvided(let pluginID):
            return .plugin(pluginID: pluginID)
        case .systemManaged:
            return .unknown
        }
    }

    static func normalizedDefinitionID(fromLegacyAgent agent: String) -> String {
        agent.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }
}

public extension AIAssetLocationScope {
    static func migrated(from scope: SkillScope) -> AIAssetLocationScope {
        switch scope {
        case .sharedAgents, .agentSpecific:
            return .userGlobal
        case .pluginProvided:
            return .bundled
        case .systemManaged:
            return .system
        }
    }
}
