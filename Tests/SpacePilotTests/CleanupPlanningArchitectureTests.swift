import Foundation
import XCTest

final class CleanupPlanningArchitectureTests: XCTestCase {
    func testAppModelPlansCleanupInDetachedWorkerWithStalePublicationGuards() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/SpacePilot/App/AppModel.swift"),
            encoding: .utf8
        )
        let body = try functionBody(
            in: source,
            signature: "func executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool)"
        )

        XCTAssertTrue(body.contains("Task.detached(priority: .userInitiated)"))
        XCTAssertTrue(body.contains("CleanupPlanner(policy: policy).makePlan"))
        XCTAssertTrue(body.contains("planningWorker.cancel()"))
        XCTAssertTrue(body.contains("cleanupOperationID == operationID"))
        XCTAssertTrue(body.contains("latestSnapshot?.id == snapshot.id"))
    }

    func testRecursiveCleanupRefreshContainsCooperativeCancellationCheck() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(
                path: "Sources/SpacePilotCore/Cleanup/CleanupCandidateRefresher.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("Task.checkCancellation()"))
        let loopBody = try block(
            in: source,
            following: "for case let url as URL in enumerator"
        )
        XCTAssertTrue(loopBody.contains("Task.checkCancellation()"))
    }

    private func functionBody(in source: String, signature: String) throws -> String {
        try block(in: source, following: signature)
    }

    private func block(in source: String, following marker: String) throws -> String {
        guard let markerRange = source.range(of: marker),
              let openingBrace = source[markerRange.upperBound...].firstIndex(of: "{") else {
            throw ArchitectureSourceError.markerNotFound(marker)
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
        throw ArchitectureSourceError.markerNotFound(marker)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

private enum ArchitectureSourceError: Error {
    case markerNotFound(String)
}
