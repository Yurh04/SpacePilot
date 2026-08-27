import Foundation

public enum ProjectAIAssetScanIssue: String, Codable, Hashable, Sendable {
    case invalidDescriptor
    case descriptorEscapesProjectRoot
    case pluginChildEscapesProjectRoot
    case projectRootMissing
    case projectRootNotDirectory
    case projectRootUnreadable
    case noSupportedAssets
}

public struct ProjectAIAssetScanResult: Sendable {
    public let skills: [SkillRecord]
    public let plugins: [PluginRecord]
    public let issues: [ProjectAIAssetScanIssue]

    public init(
        skills: [SkillRecord],
        plugins: [PluginRecord],
        issues: [ProjectAIAssetScanIssue]
    ) {
        self.skills = skills
        self.plugins = plugins
        self.issues = issues
    }
}

public struct ProjectAIAssetScanner<Scanner: SkillScanning>: Sendable {
    private let skillScanner: Scanner
    private let pluginScanner: PluginScanner<Scanner>
    private let definitions: [AIToolDefinition]

    public init(
        skillScanner: Scanner,
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) {
        self.skillScanner = skillScanner
        self.pluginScanner = PluginScanner(skillScanner: skillScanner)
        self.definitions = definitions
    }

    public func scan(approvedRoots: [ApprovedProjectRoot]) async throws -> ProjectAIAssetScanResult {
        var skills: [SkillRecord] = []
        var plugins: [PluginRecord] = []
        var issues = Set<ProjectAIAssetScanIssue>()
        var sawSupportedDescriptor = false

        for root in approvedRoots {
            try Task.checkCancellation()
            guard validateProjectRoot(root.canonicalRootURL, issues: &issues) else { continue }
            for definition in definitions {
                for descriptor in definition.projectAssetDescriptors {
                    try Task.checkCancellation()
                    sawSupportedDescriptor = true
                    guard let candidate = candidateURL(
                        descriptor.relativePath,
                        projectRoot: root.canonicalRootURL,
                        issues: &issues
                    ) else { continue }
                    let owner: AIAssetOwner = descriptor.ownership == .shared
                        ? .shared
                        : .tool(definitionID: definition.id)
                    switch descriptor.kind {
                    case .skills:
                        let discovered = try await skillScanner.scan(roots: [SkillRoot(
                            url: candidate,
                            scope: descriptor.ownership == .shared
                                ? .sharedAgents
                                : .agentSpecific(agent: definition.displayName),
                            owner: owner,
                            locationScope: .project(root.identity)
                        )])
                        skills.append(contentsOf: discovered)
                    case .plugin:
                        let result = try await pluginScanner.scan(roots: [PluginRoot(
                            url: candidate,
                            owner: owner,
                            locationScope: .project(root.identity)
                        )])
                        plugins.append(contentsOf: result.plugins)
                        skills.append(contentsOf: result.skills)
                    case .pluginContainer:
                        let roots = pluginChildren(
                            in: candidate,
                            projectRoot: root.canonicalRootURL,
                            owner: owner,
                            project: root.identity,
                            issues: &issues
                        )
                        guard !roots.isEmpty else { continue }
                        let result = try await pluginScanner.scan(roots: roots)
                        plugins.append(contentsOf: result.plugins)
                        skills.append(contentsOf: result.skills)
                    }
                }
            }
        }

        if !approvedRoots.isEmpty,
           (!sawSupportedDescriptor || (skills.isEmpty && plugins.isEmpty && issues.isEmpty)) {
            issues.insert(.noSupportedAssets)
        }

        return ProjectAIAssetScanResult(
            skills: skills.sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.url.path < rhs.url.path
            },
            plugins: plugins.sorted { lhs, rhs in
                if lhs.name != rhs.name { return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending }
                return lhs.url.path < rhs.url.path
            },
            issues: issues.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func validateProjectRoot(_ root: URL, issues: inout Set<ProjectAIAssetScanIssue>) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            issues.insert(.projectRootMissing)
            return false
        }
        guard isDirectory.boolValue else {
            issues.insert(.projectRootNotDirectory)
            return false
        }
        guard FileManager.default.isReadableFile(atPath: root.path) else {
            issues.insert(.projectRootUnreadable)
            return false
        }
        return true
    }

    private func candidateURL(
        _ relativePath: String,
        projectRoot: URL,
        issues: inout Set<ProjectAIAssetScanIssue>
    ) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.split(separator: "/").contains("..") else {
            issues.insert(.invalidDescriptor)
            return nil
        }
        let canonicalRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = projectRoot.appending(path: relativePath, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard candidate.hasPathComponentPrefix(canonicalRoot) else {
            issues.insert(.descriptorEscapesProjectRoot)
            return nil
        }
        return candidate
    }

    private func pluginChildren(
        in container: URL,
        projectRoot: URL,
        owner: AIAssetOwner,
        project: AIProjectIdentity,
        issues: inout Set<ProjectAIAssetScanIssue>
    ) -> [PluginRoot] {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: container,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let canonicalRoot = projectRoot.standardizedFileURL.resolvingSymlinksInPath()
        return children.sorted { $0.path < $1.path }.compactMap { child in
            let canonicalChild = child.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalChild.hasPathComponentPrefix(canonicalRoot) else {
                issues.insert(.pluginChildEscapesProjectRoot)
                return nil
            }
            guard (try? canonicalChild.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            return PluginRoot(
                url: canonicalChild,
                owner: owner,
                locationScope: .project(project)
            )
        }
    }
}

private extension URL {
    func hasPathComponentPrefix(_ prefix: URL) -> Bool {
        let components = pathComponents
        let prefixComponents = prefix.pathComponents
        guard prefixComponents.count <= components.count else { return false }
        return Array(components.prefix(prefixComponents.count)) == prefixComponents
    }
}
