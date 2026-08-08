import Foundation

public struct SkillRoot: Sendable {
    public let url: URL
    public let scope: SkillScope
    public let owner: AIAssetOwner
    public let locationScope: AIAssetLocationScope

    public init(
        url: URL,
        scope: SkillScope,
        owner: AIAssetOwner? = nil,
        locationScope: AIAssetLocationScope? = nil
    ) {
        self.url = url
        self.scope = scope
        self.owner = owner ?? AIAssetOwner.migrated(from: scope)
        self.locationScope = locationScope ?? AIAssetLocationScope.migrated(from: scope)
    }

    public static func production(homeDirectory: URL) -> [Self] {
        production(homeDirectory: homeDirectory, definitions: KnownAIToolDefinitions.all)
    }

    public static func production(
        homeDirectory: URL,
        definitions: [AIToolDefinition]
    ) -> [Self] {
        var byCanonicalRoot: [String: Self] = [:]
        for definition in definitions {
            for descriptor in definition.skillRoots {
                let url = homeDirectory.appending(path: descriptor.relativePath, directoryHint: .isDirectory)
                let root = Self(
                    url: url,
                    scope: descriptor.ownership == .shared
                        ? .sharedAgents
                        : .agentSpecific(agent: definition.displayName),
                    owner: descriptor.ownership == .shared
                        ? .shared
                        : .tool(definitionID: definition.id),
                    locationScope: .userGlobal
                )
                merge(root, into: &byCanonicalRoot)
            }
        }
        merge(Self(
            url: homeDirectory.appending(path: ".codex/skills/.system", directoryHint: .isDirectory),
            scope: .systemManaged,
            owner: .unknown,
            locationScope: .system
        ), into: &byCanonicalRoot)
        return byCanonicalRoot.values.sorted { $0.url.path < $1.url.path }
    }

    private static func merge(_ root: Self, into roots: inout [String: Self]) {
        let key = root.url.standardizedFileURL.resolvingSymlinksInPath().path
        guard let existing = roots[key] else {
            roots[key] = root
            return
        }
        if existing.owner == root.owner, existing.locationScope == root.locationScope { return }
        if existing.owner == .shared || root.owner == .shared {
            roots[key] = Self(url: existing.url, scope: .sharedAgents, owner: .shared, locationScope: .userGlobal)
            return
        }
        roots[key] = Self(url: existing.url, scope: existing.scope, owner: .unknown, locationScope: existing.locationScope)
    }
}

public protocol SkillScanning: Sendable {
    func scan(roots: [SkillRoot]) async throws -> [SkillRecord]
}

public struct SkillScanner: SkillScanning {
    private let parser = SkillManifestParser()

    public init() {}

    public func scan(roots: [SkillRoot]) async throws -> [SkillRecord] {
        var records: [SkillRecord] = []
        for root in roots {
            try Task.checkCancellation()
            for folder in skillFolders(at: root.url) {
                try Task.checkCancellation()
                let manifestURL = folder.appending(path: "SKILL.md")
                guard let data = try? Data(contentsOf: manifestURL) else { continue }
                let manifest = parser.parse(data)
                let metadata = folderMetadata(folder)
                records.append(SkillRecord(
                    name: manifest.name ?? folder.lastPathComponent,
                    summary: manifest.description ?? "No description",
                    url: folder.standardizedFileURL,
                    allocatedSize: metadata.allocatedSize,
                    scope: root.scope,
                    visibleAgents: visibleAgents(for: root.scope),
                    parentPluginID: nil,
                    fingerprint: ContentFingerprint.skill(
                        manifestData: data,
                        relativeFileNames: metadata.relativeFileNames
                    ),
                    conflict: nil,
                    managementStatus: managementStatus(for: root.scope),
                    owner: root.owner,
                    locationScope: root.locationScope
                ))
            }
        }
        return records.sorted {
            if $0.name == $1.name { return $0.url.path < $1.url.path }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func skillFolders(at root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        } ?? []
    }

    private func folderMetadata(_ root: URL) -> (allocatedSize: Int64, relativeFileNames: [String]) {
        let metadata = ManagedAssetDirectoryMetadata.scan(root: root)
        return (metadata.allocatedSize, metadata.relativeFileNames)
    }

    private func visibleAgents(for scope: SkillScope) -> Set<String> {
        switch scope {
        case .sharedAgents: ["Codex", "Claude"]
        case .agentSpecific(let agent): [agent]
        case .pluginProvided: ["Codex"]
        case .systemManaged: ["Codex"]
        }
    }

    private func managementStatus(for scope: SkillScope) -> SkillManagementStatus {
        switch scope {
        case .sharedAgents, .agentSpecific: .standalone
        case .pluginProvided: .parentManaged
        case .systemManaged: .systemReadOnly
        }
    }
}
