import XCTest
@testable import SpacePilotCore

final class ApprovedProjectRootTests: XCTestCase {
    func testAddingRejectsFilesystemRootFilesHomeDuplicatesAndOverlap() throws {
        let tree = try TemporaryTree(files: ["file.txt": 1])
        let project = tree.url.appending(path: "workspace/project", directoryHint: .isDirectory)
        let child = project.appending(path: "child", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let validator = ApprovedProjectRootValidator()

        XCTAssertThrowsError(try validator.adding(URL(fileURLWithPath: "/"), to: [])) {
            XCTAssertEqual($0 as? ApprovedProjectRootMutationError, .filesystemRootRejected)
        }
        XCTAssertThrowsError(try validator.adding(tree.url.appending(path: "file.txt"), to: [])) {
            XCTAssertEqual($0 as? ApprovedProjectRootMutationError, .notDirectory)
        }
        XCTAssertThrowsError(try validator.adding(project, to: [], homeDirectory: project)) {
            XCTAssertEqual($0 as? ApprovedProjectRootMutationError, .homeDirectoryRejected)
        }

        let roots = try validator.adding(project, to: [])
        XCTAssertThrowsError(try validator.adding(project, to: roots)) {
            XCTAssertEqual($0 as? ApprovedProjectRootMutationError, .duplicateRoot)
        }
        XCTAssertThrowsError(try validator.adding(child, to: roots)) {
            XCTAssertEqual($0 as? ApprovedProjectRootMutationError, .overlappingRoot)
        }
    }

    func testStoredRootsDropTamperedMissingDuplicateAndSymlinkAliasEntries() throws {
        let tree = try TemporaryTree(files: [:])
        let project = tree.url.appending(path: "project", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let alias = tree.url.appending(path: "alias", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        let valid = ApprovedProjectRoot(canonicalRootURL: project)
        let aliasRoot = ApprovedProjectRoot(canonicalRootURL: alias)
        let missing = ApprovedProjectRoot(canonicalRootURL: tree.url.appending(path: "missing"))

        let result = ApprovedProjectRootValidator().validateStored([
            valid,
            valid,
            aliasRoot,
            missing
        ])

        XCTAssertEqual(result.roots, [valid])
        XCTAssertTrue(result.issues.contains(.duplicateRoot))
        XCTAssertTrue(result.issues.contains(.missingPath))
    }
}
