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

public struct PluginRoot: Sendable {
    public let url: URL
    public let owner: AIAssetOwner
    public let locationScope: AIAssetLocationScope

    public init(
        url: URL,
        owner: AIAssetOwner = .unknown,
        locationScope: AIAssetLocationScope = .userGlobal
    ) {
        self.url = url
        self.owner = owner
        self.locationScope = locationScope
    }

    public static func production(
        homeDirectory: URL,
        discoveredRoots: [URL],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) -> [Self] {
        var byRoot: [String: Self] = [:]
        // The declared plugin roots, each paired with the owner/scope it confers.
        // A discovered plugin lives *under* one of these (for example
        // `~/.codex/plugins/cache/<src>/<plugin>/installation` sits under the
        // declared `~/.codex/plugins`), so it is attributed by path-prefix rather
        // than by an exact canonical-path match — the deep install directory never
        // equals the declared root. Deepest declared root wins when several nest.
        var declaredRoots: [(url: URL, owner: AIAssetOwner, scope: AIAssetLocationScope)] = []
        for definition in definitions {
            for descriptor in definition.pluginRoots {
                let url = homeDirectory.appending(path: descriptor.relativePath, directoryHint: .isDirectory)
                let owner: AIAssetOwner = descriptor.ownership == .shared
                    ? .shared
                    : .tool(definitionID: definition.id)
                merge(Self(url: url, owner: owner, locationScope: .userGlobal), into: &byRoot)
                declaredRoots.append((url.canonicalizedForDiscovery, owner, .userGlobal))
            }
        }
        // Longest (deepest) declared root first so a nested declaration wins over
        // a shallower one that also contains the discovered path.
        declaredRoots.sort { $0.url.pathComponents.count > $1.url.pathComponents.count }
        for root in discoveredRoots {
            let canonical = root.canonicalizedForDiscovery
            let matches = declaredRoots.filter { canonical.hasPluginPathPrefix($0.url) }
            // Among the containing roots, only the deepest ones attribute the
            // plugin; if several equally-deep roots disagree on owner (two tools
            // sharing a root), fold to an ambiguous `.unknown` rather than guess.
            let deepest = matches.first.map { $0.url.pathComponents.count }
            let winners = matches.filter { $0.url.pathComponents.count == deepest }
            let owner = winners.map(\.owner).reduce(AIAssetOwner?.none) { acc, next in
                acc.map { SkillRoot.resolveOwner($0, next) } ?? next
            } ?? .unknown
            let scope = winners.first?.scope ?? .userGlobal
            merge(Self(url: root, owner: owner, locationScope: scope), into: &byRoot)
        }
        return byRoot.values.sorted { $0.url.path < $1.url.path }
    }

    private static func merge(_ root: Self, into roots: inout [String: Self]) {
        let key = root.url.standardizedFileURL.resolvingSymlinksInPath().path
        guard let existing = roots[key] else {
            roots[key] = root
            return
        }
        let resolvedOwner = SkillRoot.resolveOwner(existing.owner, root.owner)
        if resolvedOwner == .shared {
            roots[key] = Self(url: existing.url, owner: .shared, locationScope: .userGlobal)
        } else {
            roots[key] = Self(url: existing.url, owner: resolvedOwner, locationScope: existing.locationScope)
        }
    }
}

public protocol PluginScanning: Sendable {
    func scan(roots: [PluginRoot]) async throws -> PluginScanResult
}

public struct PluginScanner<Scanner: SkillScanning>: PluginScanning {
    private let skillScanner: Scanner

    public init(skillScanner: Scanner) {
        self.skillScanner = skillScanner
    }

    public func scan(roots: [PluginRoot]) async throws -> PluginScanResult {
        var plugins: [PluginRecord] = []
        var skills: [SkillRecord] = []
        var diagnostics: [String] = []

        for rootDescriptor in roots {
            try Task.checkCancellation()
            let root = rootDescriptor.url
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
                .map { SkillRoot(
                    url: $0.deletingLastPathComponent(),
                    scope: .pluginProvided(pluginID: pluginID.uuidString),
                    owner: .plugin(pluginID: pluginID.uuidString),
                    locationScope: .bundled
                ) }
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
                        managementStatus: .parentManaged,
                        owner: .plugin(pluginID: pluginID.uuidString),
                        locationScope: .bundled
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
                managementCapability: .officialHandoff,
                owner: rootDescriptor.owner,
                locationScope: rootDescriptor.locationScope
            ))
        }

        return PluginScanResult(
            plugins: plugins.sorted { $0.name < $1.name },
            skills: skills.sorted { $0.name < $1.name },
            diagnostics: diagnostics
        )
    }

    public func scan(roots: [URL]) async throws -> PluginScanResult {
        try await scan(roots: roots.map { PluginRoot(url: $0) })
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

private extension URL {
    /// Whole-path-component prefix test on already-canonical URLs. A descendant
    /// path (`~/.codex/plugins/cache/x/install`) is under `~/.codex/plugins`, but
    /// a sibling that merely shares a string prefix (`~/.codex/plugins-backup`) is
    /// not — comparison is component-by-component, never substring.
    func hasPluginPathPrefix(_ prefix: URL) -> Bool {
        let components = pathComponents
        let prefixComponents = prefix.pathComponents
        guard prefixComponents.count <= components.count else { return false }
        return Array(components.prefix(prefixComponents.count)) == prefixComponents
    }
}
