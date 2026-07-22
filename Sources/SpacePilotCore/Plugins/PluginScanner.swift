import Foundation

public struct PluginScanResult: Sendable {
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]
    public let diagnostics: [String]

    public init(plugins: [PluginRecord], skills: [SkillRecord], diagnostics: [String]) {
        self.plugins = plugins
        self.skills = skills
        self.diagnostics = diagnostics
    }
}

public protocol PluginScanning: Sendable {
    func scan(roots: [URL]) async throws -> PluginScanResult
}

public struct PluginScanner<Scanner: SkillScanning>: PluginScanning {
    private let skillScanner: Scanner

    public init(skillScanner: Scanner) {
        self.skillScanner = skillScanner
    }

    public func scan(roots: [URL]) async throws -> PluginScanResult {
        var plugins: [PluginRecord] = []
        var skills: [SkillRecord] = []
        var diagnostics: [String] = []

        for root in roots {
            try Task.checkCancellation()
            let manifestURL = root.appending(path: ".codex-plugin/plugin.json")
            guard let data = try? Data(contentsOf: manifestURL) else {
                diagnostics.append("Missing Plugin manifest at \(manifestURL.path)")
                continue
            }
            let manifest: PluginManifest
            do {
                manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            } catch {
                diagnostics.append("Invalid Plugin manifest at \(manifestURL.path): \(error.localizedDescription)")
                continue
            }

            let pluginID = UUID()
            var acceptedFolders: [URL] = []
            for relativePath in manifest.skills {
                let folders = skillFolders(for: relativePath, beneath: root)
                if folders.isEmpty {
                    diagnostics.append("Rejected or empty Plugin skill declaration: \(relativePath)")
                } else {
                    acceptedFolders.append(contentsOf: folders)
                }
            }

            let parentRoots = Dictionary(grouping: acceptedFolders, by: { $0.deletingLastPathComponent().path })
                .values
                .compactMap(\.first)
                .map { SkillRoot(url: $0.deletingLastPathComponent(), scope: .pluginProvided(pluginID: pluginID.uuidString)) }
            let discovered = try await skillScanner.scan(roots: parentRoots)
            let acceptedPaths = Set(acceptedFolders.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
            let ownedSkills = discovered
                .filter { acceptedPaths.contains($0.url.standardizedFileURL.resolvingSymlinksInPath().path) }
                .map { skill in
                    SkillRecord(
                        id: skill.id,
                        name: skill.name,
                        summary: skill.summary,
                        url: skill.url,
                        allocatedSize: skill.allocatedSize,
                        scope: .pluginProvided(pluginID: pluginID.uuidString),
                        visibleAgents: skill.visibleAgents,
                        parentPluginID: pluginID,
                        fingerprint: skill.fingerprint,
                        conflict: skill.conflict,
                        managementStatus: .parentManaged
                    )
                }
            skills.append(contentsOf: ownedSkills)
            plugins.append(PluginRecord(
                id: pluginID,
                name: manifest.name,
                version: manifest.version,
                url: root.standardizedFileURL,
                source: root.deletingLastPathComponent().lastPathComponent,
                allocatedSize: allocatedSize(of: root),
                skillIDs: Set(ownedSkills.map(\.id)),
                dependencies: manifest.dependencies,
                managementCapability: .officialHandoff
            ))
        }

        return PluginScanResult(
            plugins: plugins.sorted { $0.name < $1.name },
            skills: skills.sorted { $0.name < $1.name },
            diagnostics: diagnostics
        )
    }

    private func validatedComponent(_ relativePath: String, beneath root: URL) -> URL? {
        guard !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else { return nil }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = root.appending(path: relativePath).standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path.hasPrefix(canonicalRoot.path + "/"),
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    private func skillFolders(for relativePath: String, beneath root: URL) -> [URL] {
        guard let candidate = validatedComponent(relativePath, beneath: root) else { return [] }
        let manifest = candidate.appending(path: "SKILL.md")
        if FileManager.default.fileExists(atPath: manifest.path) { return [candidate] }

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: candidate,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalCandidate = candidate.standardizedFileURL.resolvingSymlinksInPath()
        return children.compactMap { child in
            let canonicalChild = child.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalChild.path.hasPrefix(canonicalRoot.path + "/"),
                  canonicalChild.path.hasPrefix(canonicalCandidate.path + "/"),
                  FileManager.default.fileExists(atPath: canonicalChild.appending(path: "SKILL.md").path) else {
                return nil
            }
            return canonicalChild
        }
    }

    private func allocatedSize(of root: URL) -> Int64 {
        ManagedAssetDirectoryMetadata.scan(root: root).allocatedSize
    }
}
