import Foundation

public struct SkillRoot: Sendable {
    public let url: URL
    public let scope: SkillScope

    public init(url: URL, scope: SkillScope) {
        self.url = url
        self.scope = scope
    }

    public static func production(homeDirectory: URL) -> [Self] {
        [
            .init(url: homeDirectory.appending(path: ".agents/skills"), scope: .sharedAgents),
            .init(url: homeDirectory.appending(path: ".codex/skills"), scope: .agentSpecific(agent: "Codex")),
            .init(url: homeDirectory.appending(path: ".claude/skills"), scope: .agentSpecific(agent: "Claude")),
            .init(url: homeDirectory.appending(path: ".codex/skills/.system"), scope: .systemManaged)
        ]
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
                    managementStatus: managementStatus(for: root.scope)
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
