import XCTest
@testable import SpacePilotCore

final class ProjectRootApprovalPolicyTests: XCTestCase {
    func testUserSelectedApprovedExactRootIsAuthorized() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Projects"))
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let identity = try policy.authorize(candidateRoot: approved, source: .userSelected).get()

        XCTAssertEqual(identity.canonicalRootURL, approved.standardizedFileURL.resolvingSymlinksInPath())
        XCTAssertEqual(identity.displayName, "Projects")
    }

    func testToolConfigDescendantInsideApprovedRootIsAuthorized() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Projects"))
        let project = try directory(approved.appending(path: "SpacePilot"))
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let identity = try policy.authorize(
            candidateRoot: project,
            source: .toolConfiguration(toolID: "codex")
        ).get()

        XCTAssertEqual(identity.canonicalRootURL, project.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testToolConfigOutsideApprovedRootsIsRejectedWithSource() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Approved"))
        let outside = try directory(tree.url.appending(path: "Private"))
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let rejection = policy.authorize(
            candidateRoot: outside,
            source: .toolConfiguration(toolID: "claude")
        ).failure

        XCTAssertEqual(rejection?.reason, .outsideApprovedRoots)
        XCTAssertEqual(rejection?.source, .toolConfiguration(toolID: "claude"))
    }

    func testRootDirectoryCandidateIsRejected() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Approved"))
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let rejection = policy.authorize(
            candidateRoot: URL(fileURLWithPath: "/", isDirectory: true),
            source: .userSelected
        ).failure

        XCTAssertEqual(rejection?.reason, .rootPathNotAllowed)
    }

    func testRootDirectoryApprovedRootIsRejectedAsTooBroad() throws {
        XCTAssertThrowsError(try ProjectRootApprovalPolicy(approvedRoots: [
            URL(fileURLWithPath: "/", isDirectory: true)
        ])) { error in
            XCTAssertEqual(error as? ProjectRootRejectionReason, .approvedRootTooBroad)
        }
    }

    func testRootDirectoryApprovedRootCannotAuthorizeAnyCandidate() throws {
        let tree = try TemporaryTree(files: [:])
        let candidate = try directory(tree.url.appending(path: "Project"))

        XCTAssertThrowsError(try ProjectRootApprovalPolicy(approvedRoots: [
            URL(fileURLWithPath: "/", isDirectory: true)
        ])) { error in
            XCTAssertEqual(error as? ProjectRootRejectionReason, .approvedRootTooBroad)
        }

        let policy = try ProjectRootApprovalPolicy(approvedRoots: [])
        XCTAssertEqual(
            policy.authorize(candidateRoot: candidate, source: .userSelected).failure?.reason,
            .outsideApprovedRoots
        )
    }

    func testSimilarStringPrefixIsRejectedByPathComponents() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "foo/bar"))
        let barista = try directory(tree.url.appending(path: "foo/barista"))
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let rejection = policy.authorize(candidateRoot: barista, source: .userSelected).failure

        XCTAssertEqual(rejection?.reason, .outsideApprovedRoots)
    }

    func testDotDotIsStandardizedBeforeContainment() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Projects"))
        let project = try directory(approved.appending(path: "SpacePilot"))
        let candidate = project.appending(path: "../SpacePilot")
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let identity = try policy.authorize(candidateRoot: candidate, source: .userSelected).get()

        XCTAssertEqual(identity.canonicalRootURL, project.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testSymlinkEscapingApprovedTreeIsRejected() throws {
        let tree = try TemporaryTree(files: [:])
        let approved = try directory(tree.url.appending(path: "Approved"))
        let outside = try directory(tree.url.appending(path: "Outside"))
        let link = approved.appending(path: "escaped", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let policy = try ProjectRootApprovalPolicy(approvedRoots: [approved])

        let rejection = policy.authorize(candidateRoot: link, source: .userSelected).failure

        XCTAssertEqual(rejection?.reason, .symlinkEscapesApprovedRoots)
    }

    func testMultipleApprovedRootsAuthorizeRegardlessOfInputOrder() throws {
        let tree = try TemporaryTree(files: [:])
        let first = try directory(tree.url.appending(path: "First"))
        let second = try directory(tree.url.appending(path: "Second"))
        let project = try directory(second.appending(path: "Project"))
        let forward = try ProjectRootApprovalPolicy(approvedRoots: [first, second])
        let reversed = try ProjectRootApprovalPolicy(approvedRoots: [second, first])

        let forwardIdentity = try forward.authorize(candidateRoot: project, source: .userSelected).get()
        let reversedIdentity = try reversed.authorize(candidateRoot: project, source: .userSelected).get()

        XCTAssertEqual(forwardIdentity, reversedIdentity)
    }

    func testProjectIdentityStableIDIgnoresDisplayNameAndInputOrder() throws {
        let tree = try TemporaryTree(files: [:])
        let project = try directory(tree.url.appending(path: "Projects/SpacePilot"))
        let canonical = project.standardizedFileURL.resolvingSymlinksInPath()

        let first = AIProjectIdentity(displayName: "SpacePilot", canonicalRootURL: canonical)
        let second = AIProjectIdentity(displayName: "Renamed", canonicalRootURL: canonical)

        XCTAssertEqual(first.id, second.id)
        XCTAssertTrue(first.id.hasPrefix("project:"))
    }

    func testProjectIdentityRejectsTamperedStableIDJSON() throws {
        let tree = try TemporaryTree(files: [:])
        let project = try directory(tree.url.appending(path: "Projects/SpacePilot"))
        let identity = AIProjectIdentity(
            displayName: "SpacePilot",
            canonicalRootURL: project.standardizedFileURL.resolvingSymlinksInPath()
        )
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(identity)
        ) as? [String: Any])
        payload["id"] = "project:tampered"
        let tampered = try JSONSerialization.data(withJSONObject: payload)

        XCTAssertThrowsError(try JSONDecoder().decode(AIProjectIdentity.self, from: tampered))
    }

    private func directory(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private extension Result where Success == AIProjectIdentity, Failure == ProjectRootApprovalRejection {
    var failure: ProjectRootApprovalRejection? {
        if case .failure(let failure) = self { return failure }
        return nil
    }
}
