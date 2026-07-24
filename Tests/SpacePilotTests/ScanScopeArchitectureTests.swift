import Foundation
import XCTest

final class ScanScopeArchitectureTests: XCTestCase {
    func testFocusedRefreshDoesNotTraverseTheWholeHomeDirectory() throws {
        let source = try read(
            "Sources/SpacePilotCore/Scanning/ScanCoordinator.swift"
        )

        XCTAssertTrue(source.contains("if scope == .full"))
        XCTAssertTrue(source.contains(
            "DirectoryScanner(access: LocalFileSystemAccess()).scan"
        ))
        XCTAssertTrue(source.contains(
            "previousSnapshot?.items.filter"
        ))
    }

    func testToolbarUsesFullAnalysisOnlyForStorageViews() throws {
        let source = try read("Sources/SpacePilot/App/AppModel.swift")

        XCTAssertTrue(source.contains("case .overview, .storage:"))
        XCTAssertTrue(source.contains("case .applications:"))
        XCTAssertTrue(source.contains("case .developerAI:"))
        XCTAssertTrue(source.contains("case .history:"))
        XCTAssertTrue(source.contains("startScan(scope: scope)"))
    }

    func testCleanupUpdatesSnapshotWithoutStartingAnotherScan() throws {
        let source = try read("Sources/SpacePilot/App/AppModel.swift")
        let cleanupBody = try block(
            in: source,
            following: "func executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool)"
        )

        XCTAssertTrue(cleanupBody.contains("snapshotAfterCleanup("))
        XCTAssertTrue(cleanupBody.contains("runtime.store.save(snapshot: updated)"))
        XCTAssertFalse(cleanupBody.contains("startScan()"))
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private func block(in source: String, following marker: String) throws -> String {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            throw ScanScopeArchitectureError.markerNotFound(marker)
        }
        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[openingBrace...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }
        throw ScanScopeArchitectureError.markerNotFound(marker)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum ScanScopeArchitectureError: Error {
    case markerNotFound(String)
}
