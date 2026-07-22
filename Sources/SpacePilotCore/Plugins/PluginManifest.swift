import Foundation

public struct PluginManifest: Decodable, Sendable {
    public let name: String
    public let version: String?
    public let skills: [String]
    public let dependencies: [String]

    public init(name: String, version: String?, skills: [String], dependencies: [String]) {
        self.name = name
        self.version = version
        self.skills = skills
        self.dependencies = dependencies
    }
}
