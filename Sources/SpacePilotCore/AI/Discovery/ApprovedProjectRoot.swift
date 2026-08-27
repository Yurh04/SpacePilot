import Foundation

public enum ApprovedProjectRootIssue: String, Codable, Hashable, Sendable {
    case invalidPayload
    case tamperedIdentity
    case missingPath
    case notDirectory
    case unreadableDirectory
    case filesystemRootRejected
    case homeDirectoryRejected
    case duplicateRoot
    case symlinkAliasDuplicate
    case overlappingRoot
}

public struct ApprovedProjectRoot: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let identity: AIProjectIdentity
    public let canonicalRootURL: URL
    public let selectedAt: Date

    public init(canonicalRootURL: URL, selectedAt: Date = .now) {
        let canonicalRootURL = canonicalRootURL.standardizedFileURL.resolvingSymlinksInPath()
        let identity = AIProjectIdentity(
            displayName: canonicalRootURL.lastPathComponent,
            canonicalRootURL: canonicalRootURL
        )
        self.id = identity.id
        self.identity = identity
        self.canonicalRootURL = canonicalRootURL
        self.selectedAt = selectedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case identity
        case canonicalRootURL
        case selectedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let identity = try container.decode(AIProjectIdentity.self, forKey: .identity)
        let canonicalRootURL = try container.decode(URL.self, forKey: .canonicalRootURL)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard identity.canonicalRootURL == canonicalRootURL,
              id == identity.id else {
            throw DecodingError.dataCorruptedError(
                forKey: .id,
                in: container,
                debugDescription: "ApprovedProjectRoot id does not match canonicalRootURL"
            )
        }
        self.id = id
        self.identity = identity
        self.canonicalRootURL = canonicalRootURL
        selectedAt = try container.decode(Date.self, forKey: .selectedAt)
    }
}

public struct ApprovedProjectRootValidationResult: Sendable {
    public let roots: [ApprovedProjectRoot]
    public let issues: [ApprovedProjectRootIssue]

    public init(roots: [ApprovedProjectRoot], issues: [ApprovedProjectRootIssue]) {
        self.roots = roots
        self.issues = issues
    }
}

public enum ApprovedProjectRootMutationError: Error, Equatable, Sendable {
    case filesystemRootRejected
    case homeDirectoryRejected
    case notDirectory
    case unreadableDirectory
    case duplicateRoot
    case overlappingRoot
}

public protocol ApprovedProjectRootStoring: Sendable {
    func load() throws -> ApprovedProjectRootValidationResult
    func replace(_ roots: [ApprovedProjectRoot]) throws
}

public struct ApprovedProjectRootValidator: Sendable {
    public init() {}

    public func validateStored(_ roots: [ApprovedProjectRoot]) -> ApprovedProjectRootValidationResult {
        normalize(roots, dropInvalid: true)
    }

    public func adding(
        _ url: URL,
        to roots: [ApprovedProjectRoot],
        homeDirectory: URL? = nil,
        selectedAt: Date = .now
    ) throws -> [ApprovedProjectRoot] {
        let root = try makeRoot(from: url, homeDirectory: homeDirectory, selectedAt: selectedAt)
        var next = roots
        next.append(root)
        let normalized = normalize(next, dropInvalid: false)
        if normalized.issues.contains(.duplicateRoot) || normalized.issues.contains(.symlinkAliasDuplicate) {
            throw ApprovedProjectRootMutationError.duplicateRoot
        }
        if normalized.issues.contains(.overlappingRoot) {
            throw ApprovedProjectRootMutationError.overlappingRoot
        }
        return normalized.roots
    }

    public func removing(id: String, from roots: [ApprovedProjectRoot]) -> [ApprovedProjectRoot] {
        roots.filter { $0.id != id }
    }

    private func makeRoot(from url: URL, homeDirectory: URL?, selectedAt: Date) throws -> ApprovedProjectRoot {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard !canonical.isFilesystemRoot else { throw ApprovedProjectRootMutationError.filesystemRootRejected }
        if let homeDirectory,
           canonical == homeDirectory.standardizedFileURL.resolvingSymlinksInPath() {
            throw ApprovedProjectRootMutationError.homeDirectoryRejected
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory) else {
            throw ApprovedProjectRootMutationError.notDirectory
        }
        guard isDirectory.boolValue else { throw ApprovedProjectRootMutationError.notDirectory }
        guard FileManager.default.isReadableFile(atPath: canonical.path) else {
            throw ApprovedProjectRootMutationError.unreadableDirectory
        }
        return ApprovedProjectRoot(canonicalRootURL: canonical, selectedAt: selectedAt)
    }

    private func normalize(
        _ roots: [ApprovedProjectRoot],
        dropInvalid: Bool
    ) -> ApprovedProjectRootValidationResult {
        var kept: [ApprovedProjectRoot] = []
        var seenIDs = Set<String>()
        var seenPaths = Set<String>()
        var issues = Set<ApprovedProjectRootIssue>()

        for root in roots.sorted(by: rootOrder) {
            guard root.id == AIProjectIdentity.stableID(for: root.canonicalRootURL),
                  root.id == root.identity.id,
                  root.identity.canonicalRootURL == root.canonicalRootURL else {
                issues.insert(.tamperedIdentity)
                if dropInvalid { continue }
                continue
            }
            guard !root.canonicalRootURL.isFilesystemRoot else {
                issues.insert(.filesystemRootRejected)
                if dropInvalid { continue }
                continue
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.canonicalRootURL.path, isDirectory: &isDirectory) else {
                issues.insert(.missingPath)
                if dropInvalid { continue }
                continue
            }
            guard isDirectory.boolValue else {
                issues.insert(.notDirectory)
                if dropInvalid { continue }
                continue
            }
            guard FileManager.default.isReadableFile(atPath: root.canonicalRootURL.path) else {
                issues.insert(.unreadableDirectory)
                if dropInvalid { continue }
                continue
            }
            guard seenIDs.insert(root.id).inserted else {
                issues.insert(.duplicateRoot)
                if dropInvalid { continue }
                continue
            }
            guard seenPaths.insert(root.canonicalRootURL.path).inserted else {
                issues.insert(.symlinkAliasDuplicate)
                if dropInvalid { continue }
                continue
            }
            if kept.contains(where: { root.canonicalRootURL.hasPathComponentPrefix($0.canonicalRootURL) || $0.canonicalRootURL.hasPathComponentPrefix(root.canonicalRootURL) }) {
                issues.insert(.overlappingRoot)
                if dropInvalid { continue }
                continue
            }
            kept.append(root)
        }
        return ApprovedProjectRootValidationResult(roots: kept, issues: issues.sorted { $0.rawValue < $1.rawValue })
    }

    private func rootOrder(_ lhs: ApprovedProjectRoot, _ rhs: ApprovedProjectRoot) -> Bool {
        if lhs.selectedAt != rhs.selectedAt { return lhs.selectedAt < rhs.selectedAt }
        return lhs.canonicalRootURL.path < rhs.canonicalRootURL.path
    }
}

private extension URL {
    var isFilesystemRoot: Bool { pathComponents == ["/"] }

    func hasPathComponentPrefix(_ prefix: URL) -> Bool {
        let components = pathComponents
        let prefixComponents = prefix.pathComponents
        guard prefixComponents.count <= components.count else { return false }
        return Array(components.prefix(prefixComponents.count)) == prefixComponents
    }
}
