import Foundation

public struct PluginManifest: Decodable, Sendable {
    public let name: String
    public let version: String?
    public let skills: [String]
    public let dependencies: [String]

    private enum CodingKeys: String, CodingKey {
        case name, version, skills, dependencies
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        dependencies = try values.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        if let path = try? values.decode(String.self, forKey: .skills) {
            skills = [path]
        } else {
            skills = try values.decodeIfPresent([String].self, forKey: .skills) ?? []
        }
    }

    public init(name: String, version: String?, skills: [String], dependencies: [String]) {
        self.name = name
        self.version = version
        self.skills = skills
        self.dependencies = dependencies
    }
}
