import Foundation

public enum ProjectRootCandidateSource: Codable, Hashable, Sendable {
    case userSelected
    case toolConfiguration(toolID: String)
}

public enum ProjectRootRejectionReason: String, Error, Codable, Hashable, Sendable {
    case emptyPath
    case rootPathNotAllowed
    case approvedRootTooBroad
    case outsideApprovedRoots
    case symlinkEscapesApprovedRoots
}

public struct ProjectRootApprovalRejection: Error, Codable, Hashable, Sendable {
    public let source: ProjectRootCandidateSource
    public let reason: ProjectRootRejectionReason
    public let candidateURL: URL

    public init(
        source: ProjectRootCandidateSource,
        reason: ProjectRootRejectionReason,
        candidateURL: URL
    ) {
        self.source = source
        self.reason = reason
        self.candidateURL = candidateURL
    }
}

public struct ProjectRootApprovalPolicy: Sendable {
    private let approvedRoots: [URL]

    public init(approvedRoots: [URL]) throws {
        self.approvedRoots = try approvedRoots.map(Self.canonicalApprovedRoot)
            .sorted { lhs, rhs in
                let lhsComponents = lhs.pathComponents.count
                let rhsComponents = rhs.pathComponents.count
                if lhsComponents != rhsComponents { return lhsComponents > rhsComponents }
                return lhs.path < rhs.path
            }
    }

    public func authorize(
        candidateRoot: URL,
        source: ProjectRootCandidateSource
    ) -> Result<AIProjectIdentity, ProjectRootApprovalRejection> {
        guard !candidateRoot.path.isEmpty else {
            return .failure(ProjectRootApprovalRejection(
                source: source,
                reason: .emptyPath,
                candidateURL: candidateRoot
            ))
        }
        let standardized = candidateRoot.standardizedFileURL
        guard !standardized.isFilesystemRoot else {
            return .failure(ProjectRootApprovalRejection(
                source: source,
                reason: .rootPathNotAllowed,
                candidateURL: candidateRoot
            ))
        }
        guard containsApprovedRoot(standardized) else {
            return .failure(ProjectRootApprovalRejection(
                source: source,
                reason: .outsideApprovedRoots,
                candidateURL: candidateRoot
            ))
        }

        let canonical = Self.canonical(candidateRoot)
        guard !canonical.isFilesystemRoot else {
            return .failure(ProjectRootApprovalRejection(
                source: source,
                reason: .rootPathNotAllowed,
                candidateURL: candidateRoot
            ))
        }
        guard containsApprovedRoot(canonical) else {
            return .failure(ProjectRootApprovalRejection(
                source: source,
                reason: .symlinkEscapesApprovedRoots,
                candidateURL: candidateRoot
            ))
        }

        return .success(AIProjectIdentity(
            displayName: canonical.lastPathComponent,
            canonicalRootURL: canonical
        ))
    }

    private func containsApprovedRoot(_ candidate: URL) -> Bool {
        approvedRoots.contains { approvedRoot in
            candidate.hasPathComponentPrefix(approvedRoot)
        }
    }

    private static func canonicalApprovedRoot(_ url: URL) throws -> URL {
        let canonical = canonical(url)
        guard !canonical.path.isEmpty else {
            throw ProjectRootRejectionReason.emptyPath
        }
        guard !canonical.isFilesystemRoot else {
            throw ProjectRootRejectionReason.approvedRootTooBroad
        }
        return canonical
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
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
