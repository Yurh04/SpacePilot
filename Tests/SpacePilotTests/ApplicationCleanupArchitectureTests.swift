import Foundation
import XCTest

final class ApplicationCleanupArchitectureTests: XCTestCase {
    func testApplicationCleanupHandlersUseBoundedProjectionInputs() throws {
        let source = try source(at: "Sources/SpacePilot/App/AppModel.swift")
        let uninstall = try functionBody(
            in: source,
            signature: "func prepareUninstall(application: ApplicationProjection)"
        )
        let reset = try functionBody(
            in: source,
            signature: "func prepareReset(application: ApplicationProjection)"
        )

        assertNoFullSnapshotTraversal(in: uninstall, handler: "prepareUninstall")
        assertNoFullSnapshotTraversal(in: reset, handler: "prepareReset")
        XCTAssertTrue(
            uninstall.contains("ApplicationUninstallPlanner().cleanupItems(for: application)"),
            "prepareUninstall must pass its bounded projection directly to the planner"
        )
        XCTAssertTrue(
            reset.contains("ApplicationUninstallPlanner().resetItems(for: application)"),
            "prepareReset must pass its bounded projection directly to the planner"
        )
    }

    func testApplicationViewKeepsProjectionCallbacksForContextMenuAndDetailActions() throws {
        let source = try source(at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift")
        let normalized = source.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let contextMenu = try block(in: source, following: ".contextMenu")

        XCTAssertTrue(
            normalized.range(
                of: #"let uninstall\s*:\s*\(\s*ApplicationProjection\s*\)\s*->\s*Void"#,
                options: .regularExpression
            ) != nil
        )
        XCTAssertTrue(
            normalized.range(
                of: #"let reset\s*:\s*\(\s*ApplicationProjection\s*\)\s*->\s*Void"#,
                options: .regularExpression
            ) != nil
        )
        XCTAssertTrue(contextMenu.contains("reset(projection)"))
        XCTAssertTrue(contextMenu.contains("uninstall(projection)"))
        XCTAssertTrue(
            normalized.contains(
                "ApplicationDetail( projection: application, uninstall: { uninstall(application) }, reset: { reset(application) } )"
            ),
            "Detail actions must forward the selected ApplicationProjection"
        )
    }

    func testAppModelAdaptsReviewRowsWithoutBroadeningCleanupPlannerSelection() throws {
        let source = try source(at: "Sources/SpacePilot/App/AppModel.swift")

        XCTAssertTrue(source.contains("var cleanupCandidates: [CleanupReviewItem] = []"))
        XCTAssertTrue(source.contains(
            "CleanupReviewItem(item: $0, ownership: .owned, evidence: nil)"
        ))
        XCTAssertTrue(source.contains("let candidateItems = cleanupCandidates.map(\\.item)"))
        XCTAssertTrue(source.contains("items: candidateItems"))
        XCTAssertTrue(source.contains("selectedIDs: eligibleSelectedIDs"))
    }

    private func assertNoFullSnapshotTraversal(
        in body: String,
        handler: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lowercaseBody = body.lowercased()
        let forbiddenTokens = ["latestsnapshot", "scansnapshot", "snapshot", ".items"]
        for token in forbiddenTokens {
            XCTAssertFalse(
                lowercaseBody.contains(token),
                "\(handler) must not access a snapshot or its full item collection (found \(token))",
                file: file,
                line: line
            )
        }
    }

    private func source(at relativePath: String) throws -> String {
        try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }

    private func functionBody(in source: String, signature: String) throws -> String {
        guard let signatureRange = source.range(of: signature) else {
            throw ArchitectureSourceError.markerNotFound(signature)
        }
        return try block(in: source, followingIndex: signatureRange.upperBound, marker: signature)
    }

    private func block(in source: String, following marker: String) throws -> String {
        guard let markerRange = source.range(of: marker) else {
            throw ArchitectureSourceError.markerNotFound(marker)
        }
        return try block(in: source, followingIndex: markerRange.upperBound, marker: marker)
    }

    private func block(
        in source: String,
        followingIndex: String.Index,
        marker: String
    ) throws -> String {
        guard let openingBrace = source[followingIndex...].firstIndex(of: "{") else {
            throw ArchitectureSourceError.openingBraceNotFound(marker)
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
        throw ArchitectureSourceError.closingBraceNotFound(marker)
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
    case openingBraceNotFound(String)
    case closingBraceNotFound(String)
}
