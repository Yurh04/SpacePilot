import Foundation

public struct SkillManifest: Sendable {
    public let name: String?
    public let description: String?
}

public struct SkillManifestParser: Sendable {
    public init() {}

    public func parse(_ data: Data) -> SkillManifest {
        guard let text = String(data: data, encoding: .utf8) else {
            return SkillManifest(name: nil, description: nil)
        }
        var name: String?
        var description: String?
        var insideFrontMatter = false
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                if insideFrontMatter { break }
                insideFrontMatter = true
                continue
            }
            guard insideFrontMatter, let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: separator)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key == "name" { name = value }
            if key == "description" { description = value }
        }
        return SkillManifest(name: name, description: description)
    }
}
