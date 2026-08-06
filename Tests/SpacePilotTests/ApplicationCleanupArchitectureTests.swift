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
            normalized.range(
                of: #"ApplicationDetail\(\s*projection:\s*application,.*uninstall:\s*\{\s*uninstall\(application\)\s*\},\s*reset:\s*\{\s*reset\(application\)\s*\}\s*\)"#,
                options: .regularExpression
            ) != nil,
            "Detail actions must forward the selected ApplicationProjection"
        )
    }

    func testApplicationAndRelatedFileSearchesUseIndependentState() throws {
        let applicationsSource = try source(
            at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift"
        )
        let root = try source(at: "Sources/SpacePilot/Views/AppRootView.swift")

        XCTAssertTrue(applicationsSource.contains("@State private var applicationSearchText"))
        XCTAssertTrue(applicationsSource.contains(
            "matching: applicationSearchText"
        ))
        XCTAssertTrue(applicationsSource.contains(
            "sortedBy: applicationSortOrder"
        ))
        XCTAssertTrue(applicationsSource.contains(
            "let relatedFileSearchText: String"
        ))
        XCTAssertTrue(applicationsSource.contains(
            "pair.item.url.path.localizedCaseInsensitiveContains(query)"
        ))
        XCTAssertTrue(root.contains(
            "relatedFileSearchText: model.searchText"
        ))
    }

    func testApplicationScreenUsesHorizontalListAndDetailLayout() throws {
        let source = try source(
            at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift"
        )

        let splitIndex = try XCTUnwrap(source.range(of: "HSplitView"))
        let listIndex = try XCTUnwrap(source.range(of: "ApplicationListPane("))
        let detailIndex = try XCTUnwrap(source.range(of: "ApplicationDetail("))

        XCTAssertLessThan(splitIndex.lowerBound, listIndex.lowerBound)
        XCTAssertLessThan(listIndex.lowerBound, detailIndex.lowerBound)
        XCTAssertTrue(source.contains(".frame(width: 280)"))
        XCTAssertFalse(
            source.contains(
                ".frame(minWidth: 230, idealWidth: 280, maxWidth: 340)"
            ),
            "The application list must not resize when detail analysis changes its ideal size"
        )
        XCTAssertTrue(source.contains(
            ".frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)"
        ))
        XCTAssertTrue(source.contains(".listStyle(.sidebar)"))
    }

    func testAppModelAdaptsReviewRowsWithoutBroadeningCleanupPlannerSelection() throws {
        let source = try source(at: "Sources/SpacePilot/App/AppModel.swift")

        XCTAssertTrue(source.contains("var cleanupCandidates: [CleanupReviewItem] = []"))
        XCTAssertTrue(source.contains(
            "CleanupReviewItem(item: $0, ownership: .owned, evidence: nil)"
        ))
        XCTAssertTrue(source.contains("let candidateItems = cleanupCandidates.map(\\.item)"))
        XCTAssertTrue(source.contains("$0.effectiveRisk != .managed"))
        XCTAssertTrue(source.contains("$0.effectiveRisk == .sensitive"))
        XCTAssertTrue(source.contains("items: candidateItems"))
        XCTAssertTrue(source.contains("selectedIDs: eligibleSelectedIDs"))
    }

    func testNativeFileIconIsBoundedCachedAndUsedInEveryRequestedFileList() throws {
        let icon = try source(
            at: "Sources/SpacePilot/Views/Shared/FileSystemItemIcon.swift"
        )
        let applications = try source(
            at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift"
        )
        let cleanup = try source(
            at: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift"
        )
        let storage = try source(
            at: "Sources/SpacePilot/Views/Shared/StorageItemRow.swift"
        )

        XCTAssertTrue(icon.contains("images.countLimit = 512"))
        XCTAssertTrue(icon.contains("url.standardizedFileURL.path"))
        XCTAssertTrue(icon.contains("NSWorkspace.shared.icon(forFile:"))
        XCTAssertTrue(icon.contains(".accessibilityHidden(true)"))
        XCTAssertFalse(icon.contains("FileManager"))
        XCTAssertFalse(icon.contains("enumerator("))
        XCTAssertFalse(icon.contains("contentsOfDirectory"))

        XCTAssertGreaterThanOrEqual(
            applications.components(separatedBy: "FileSystemItemIcon(url:").count - 1,
            2,
            "Both the application and its association rows must use native icons"
        )
        XCTAssertTrue(cleanup.contains("FileSystemItemIcon(url: item.url"))
        XCTAssertTrue(storage.contains("FileSystemItemIcon(url: item.url"))
    }

    func testAssociationAndCleanupRowsPresentLocalizedOwnershipAndSharedWarnings() throws {
        let applications = try source(
            at: "Sources/SpacePilot/Views/Applications/ApplicationsView.swift"
        )
        let cleanup = try source(
            at: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift"
        )

        for source in [applications, cleanup] {
            XCTAssertTrue(source.contains("L10n.name(for:"))
            XCTAssertTrue(source.contains("ownership"))
            XCTAssertTrue(source.contains("exclamationmark.triangle"))
        }
        XCTAssertTrue(applications.contains("max(pair.item.risk, pair.association.risk)"))
        XCTAssertTrue(cleanup.contains("reviewItem.effectiveRisk"))
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
