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
            owner: .tool(definitionID: "codex"),
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
        let resolvedOwner = Self.resolveOwner(existing.owner, root.owner)
        // Shared ownership normalizes the scope to a userGlobal shared agents root;
        // otherwise keep the existing scope/locationScope (they refer to the same path).
        if resolvedOwner == .shared {
            roots[key] = Self(url: existing.url, scope: .sharedAgents, owner: .shared, locationScope: .userGlobal)
        } else {
            roots[key] = Self(url: existing.url, scope: existing.scope, owner: resolvedOwner, locationScope: existing.locationScope)
        }
    }

    /// Order-independent owner precedence for two descriptors that resolve to the same
    /// canonical root. Fixed attribution beats weak discovery:
    /// - equal owners: keep as-is
    /// - either `.shared`: shared wins (public overlap)
    /// - one concrete `.tool` and the other `.unknown`: keep the concrete tool
    /// - two *different* concrete tools: genuinely ambiguous -> `.unknown`
    static func resolveOwner(_ lhs: AIAssetOwner, _ rhs: AIAssetOwner) -> AIAssetOwner {
        if lhs == rhs { return lhs }
        if lhs == .shared || rhs == .shared { return .shared }
        if lhs == .unknown { return rhs }
        if rhs == .unknown { return lhs }
        // Two distinct concrete owners (e.g. two different tools) -> ambiguous.
        return .unknown
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
                let symlink = symlinkInfo(for: folder)
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
                    locationScope: root.locationScope,
                    symlinkTarget: symlink.target,
                    isSymlinkBroken: symlink.isBroken
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
        ))?.filter { url in
            // A real directory, or a symlink that resolves to a directory — a
            // skill exposed through a symlink (for example a manager that links
            // its store into the Agent's skills folder) must still be scanned.
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                return true
            }
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        } ?? []
    }

    private func folderMetadata(_ root: URL) -> (allocatedSize: Int64, relativeFileNames: [String]) {
        let metadata = ManagedAssetDirectoryMetadata.scan(root: root)
        return (metadata.allocatedSize, metadata.relativeFileNames)
    }

    /// Reports whether a skill folder is itself a symbolic link, its resolved
    /// target, and whether that target is missing (a broken link). A skill exposed
    /// only through a symlink is at the mercy of whatever owns the target: if the
    /// target's manager is uninstalled the skill silently stops loading, which is
    /// exactly the kind of fragile dependency the overview surfaces. Only the link
    /// itself is inspected — no content is read.
    private func symlinkInfo(for folder: URL) -> (target: URL?, isBroken: Bool) {
        let fm = FileManager.default
        let values = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey])
        guard values?.isSymbolicLink == true else { return (nil, false) }
        // Resolve the link. `destinationOfSymbolicLink` may be relative, so resolve
        // it against the link's parent before checking existence.
        guard let destination = try? fm.destinationOfSymbolicLink(atPath: folder.path) else {
            return (nil, true)
        }
        let target = (destination as NSString).isAbsolutePath
            ? URL(fileURLWithPath: destination)
            : folder.deletingLastPathComponent().appending(path: destination)
        let resolved = target.standardizedFileURL
        let isBroken = !fm.fileExists(atPath: resolved.path)
        return (resolved, isBroken)
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
