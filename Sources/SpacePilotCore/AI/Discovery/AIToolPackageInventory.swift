import Foundation

public struct AIToolPackageInstallFact: Codable, Hashable, Sendable {
    public let definitionID: String
    public let manager: AIToolPackageManager
    public let packageName: String
    public let version: String?
    public let metadataURL: URL

    public init(
        definitionID: String,
        manager: AIToolPackageManager,
        packageName: String,
        version: String?,
        metadataURL: URL
    ) {
        self.definitionID = definitionID
        self.manager = manager
        self.packageName = packageName
        self.version = version
        self.metadataURL = metadataURL
    }
}

public protocol AIToolPackageMetadataReading: Sendable {
    func metadataData(at url: URL) throws -> Data?
}

public struct LocalAIToolPackageMetadataReader: AIToolPackageMetadataReading {
    public init() {}

    public func metadataData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }
}

public struct AIToolPackageInventory: Sendable {
    private let definitions: [AIToolDefinition]
    private let reader: any AIToolPackageMetadataReading

    public init(
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all,
        reader: any AIToolPackageMetadataReading = LocalAIToolPackageMetadataReader()
    ) {
        self.definitions = definitions
        self.reader = reader
    }

    /// Reads only fixed, definition-owned package metadata locations and emits
    /// install facts. Receipt fields such as bin/scripts/command/executable are
    /// intentionally ignored and never become probe candidates or update plans.
    public func installedPackages(homeDirectory: URL) throws -> [AIToolPackageInstallFact] {
        var facts: [AIToolPackageInstallFact] = []
        var seen = Set<String>()

        for definition in definitions {
            for descriptor in definition.packageDescriptors {
                for relativePath in descriptor.metadataRelativePaths {
                    let metadataURL = homeDirectory.appending(
                        path: relativePath,
                        directoryHint: .notDirectory
                    )
                    guard let data = try reader.metadataData(at: metadataURL) else { continue }
                    let parsed = Self.parseMetadata(data)
                    let packageName = parsed.packageName ?? descriptor.packageName
                    guard packageName == descriptor.packageName else { continue }
                    let canonical = metadataURL.standardizedFileURL.resolvingSymlinksInPath().path
                    let key = "\(definition.id)|\(descriptor.manager.rawValue)|\(packageName)|\(canonical)"
                    guard seen.insert(key).inserted else { continue }
                    facts.append(AIToolPackageInstallFact(
                        definitionID: definition.id,
                        manager: descriptor.manager,
                        packageName: packageName,
                        version: parsed.version,
                        metadataURL: metadataURL
                    ))
                }
            }
        }

        return facts
    }

    private static func parseMetadata(_ data: Data) -> (packageName: String?, version: String?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, nil)
        }

        let packageName = object["name"] as? String
            ?? object["package"] as? String
            ?? object["packageName"] as? String
        let version = object["version"] as? String
            ?? object["package_version"] as? String

        return (packageName, version)
    }
}
