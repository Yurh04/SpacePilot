import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationAssociationKnowledgeBaseTests: XCTestCase {
    func testCodableRoundTripPreservesVersionedRules() throws {
        let original = ApplicationAssociationKnowledgeBase.builtInV1

        let data = try original.encoded()
        let decoded = try ApplicationAssociationKnowledgeBase.decode(data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.contentVersion, "1.2.0")
        XCTAssertEqual(decoded.rules.count, 10)
    }

    func testMatchesExactBundleAndTeamIdentifiers() throws {
        let fixture = try Fixture()
        let knowledgeBase = ApplicationAssociationKnowledgeBase(
            schemaVersion: 1,
            contentVersion: "test",
            rules: [
                rule(
                    match: ApplicationAssociationKnowledgeMatch(
                        bundleIdentifiers: ["com.example.Editor"],
                        teamIdentifiers: ["TEAM123"]
                    )
                )
            ]
        )
        let matchingContext = fixture.context(
            bundleIdentifier: "com.example.Editor",
            teamIdentifier: "TEAM123"
        )
        let wrongTeamContext = fixture.context(
            bundleIdentifier: "com.example.Editor",
            teamIdentifier: "OTHER"
        )

        let matches = try knowledgeBase.candidates(
            for: matchingContext,
            homeDirectory: fixture.home
        )
        let nonmatches = try knowledgeBase.candidates(
            for: wrongTeamContext,
            homeDirectory: fixture.home
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].url.path, fixture.home
            .appending(path: "Library/Caches/com.example.Editor").path)
        XCTAssertEqual(matches[0].disposition, .inspectOnly)
        XCTAssertTrue(nonmatches.isEmpty)
    }

    func testFrameworkMarkerEnablesElectronRule() throws {
        let fixture = try Fixture()
        let marker = fixture.applicationBundle
            .appending(path: "Contents/Frameworks/Electron Framework.framework")
        try FileManager.default.createDirectory(
            at: marker,
            withIntermediateDirectories: true
        )

        let candidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.example.electron",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )

        let electronCandidates = candidates.filter {
            $0.ruleID == "framework.electron.v1"
        }
        XCTAssertEqual(electronCandidates.count, 3)
        XCTAssertTrue(electronCandidates.allSatisfy {
            $0.disposition == .inspectOnly
        })
        XCTAssertTrue(electronCandidates.contains {
            $0.category == .cache
                && $0.risk == .rebuildable
                && $0.confidence == .medium
                && $0.ownership == .owned
                && $0.evidence == .knownRule
        })
    }

    func testExclusionPathsAreResolvedInsideSameScope() throws {
        let fixture = try Fixture()
        let knowledgeBase = ApplicationAssociationKnowledgeBase(
            schemaVersion: 1,
            contentVersion: "test",
            rules: [
                ApplicationAssociationKnowledgeRule(
                    id: "exclusion",
                    match: ApplicationAssociationKnowledgeMatch(
                        bundleIdentifiers: ["com.example.Editor"]
                    ),
                    paths: [
                        ApplicationAssociationPathRule(
                            scope: .homeDirectory,
                            template: "Library/Application Support/Editor",
                            excludedPaths: [
                                "Library/Application Support/Editor/User Data"
                            ],
                            category: .application,
                            risk: .sensitive,
                            confidence: .high,
                            ownership: .owned
                        )
                    ]
                )
            ]
        )

        let candidate = try XCTUnwrap(
            knowledgeBase.candidates(
                for: fixture.context(
                    bundleIdentifier: "com.example.Editor",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            ).first
        )

        XCTAssertEqual(
            candidate.excludedURLs,
            [
                fixture.home.appending(
                    path: "Library/Application Support/Editor/User Data"
                )
            ]
        )
    }

    func testDecodeRejectsUnsupportedSchemaAndDuplicateRules() throws {
        let unsupported = ApplicationAssociationKnowledgeBase(
            schemaVersion: 2,
            contentVersion: "test",
            rules: []
        )
        XCTAssertThrowsError(
            try ApplicationAssociationKnowledgeBase.decode(
                JSONEncoder().encode(unsupported)
            )
        ) {
            XCTAssertEqual(
                $0 as? ApplicationAssociationKnowledgeError,
                .unsupportedSchemaVersion(2)
            )
        }

        let duplicate = ApplicationAssociationKnowledgeBase(
            schemaVersion: 1,
            contentVersion: "test",
            rules: [rule(id: "duplicate"), rule(id: "duplicate")]
        )
        XCTAssertThrowsError(try duplicate.encoded()) {
            XCTAssertEqual(
                $0 as? ApplicationAssociationKnowledgeError,
                .duplicateRuleID("duplicate")
            )
        }
    }

    func testValidationRejectsAbsoluteTraversalAndUnknownPlaceholderPaths() {
        for unsafePath in [
            "/Library/Caches/app",
            "../Library/Caches/app",
            "Library/../Caches/app",
            "~/Library/Caches/app"
        ] {
            let knowledgeBase = knowledgeBase(path: unsafePath)
            XCTAssertThrowsError(try knowledgeBase.encoded()) {
                XCTAssertEqual(
                    $0 as? ApplicationAssociationKnowledgeError,
                    .unsafeRelativePath(unsafePath)
                )
            }
        }

        let unknown = "Library/Caches/{unknown}"
        XCTAssertThrowsError(try knowledgeBase(path: unknown).encoded()) {
            XCTAssertEqual(
                $0 as? ApplicationAssociationKnowledgeError,
                .unknownPlaceholder(unknown)
            )
        }
    }

    func testResolutionRejectsEscapingPlaceholderValue() throws {
        let fixture = try Fixture()
        let context = ApplicationAssociationKnowledgeContext(
            applicationName: "../Outside",
            bundleIdentifier: "com.example.Editor",
            teamIdentifier: nil,
            applicationBundleURL: fixture.applicationBundle
        )
        let knowledgeBase = knowledgeBase(
            path: "Library/Application Support/{appName}"
        )

        XCTAssertThrowsError(
            try knowledgeBase.candidates(
                for: context,
                homeDirectory: fixture.home
            )
        ) {
            XCTAssertEqual(
                $0 as? ApplicationAssociationKnowledgeError,
                .unsafePlaceholderValue("{appName}")
            )
        }
    }

    func testResolutionRejectsSymlinkEscapingHomeScope() throws {
        let fixture = try Fixture()
        let outside = fixture.root.appending(path: "Outside")
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: true
        )
        let library = fixture.home.appending(path: "Library")
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: library.appending(path: "Escape"),
            withDestinationURL: outside
        )
        let unsafeTemplate = "Library/Escape/file"
        let knowledgeBase = knowledgeBase(path: unsafeTemplate)

        XCTAssertThrowsError(
            try knowledgeBase.candidates(
                for: fixture.context(
                    bundleIdentifier: "com.example.Editor",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        ) {
            XCTAssertEqual(
                $0 as? ApplicationAssociationKnowledgeError,
                .pathEscapesScope(unsafeTemplate)
            )
        }
    }

    func testBuiltInHomebrewAndNativeMessagingRulesAreConservative() throws {
        let fixture = try Fixture()
        let codexCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.openai.codex",
                    teamIdentifier: "2DC432GLL2"
                ),
                homeDirectory: fixture.home
            )
        let nativeMessaging = try XCTUnwrap(codexCandidates.first {
            $0.ruleID == "integration.chrome-native-messaging.openai-codex.v1"
        })
        XCTAssertEqual(nativeMessaging.ownership, .owned)
        XCTAssertEqual(nativeMessaging.risk, .rebuildable)
        XCTAssertEqual(nativeMessaging.disposition, .inspectOnly)
        let codexSupportPaths = Set(codexCandidates.filter {
            $0.ruleID == "product.openai.chatgpt-codex.v1"
        }.map(\.url.lastPathComponent))
        XCTAssertEqual(codexSupportPaths, ["Codex"])
        XCTAssertEqual(
            codexCandidates.filter {
                $0.ruleID == "product.openai.chatgpt-codex.v1"
            }.count,
            2
        )

        let dockerCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.docker.docker",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        let homebrew = try XCTUnwrap(dockerCandidates.first {
            $0.ruleID == "installer.homebrew-cask.docker.v1"
        })
        XCTAssertEqual(homebrew.confidence, .low)
        XCTAssertEqual(homebrew.ownership, .shared)
        XCTAssertEqual(homebrew.risk, .sensitive)
        XCTAssertEqual(homebrew.disposition, .inspectOnly)
    }

    func testBuiltInEditorRulesFindHiddenUserDataConservatively() throws {
        let fixture = try Fixture()
        let vscodeCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.microsoft.VSCode",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        let vscode = try XCTUnwrap(vscodeCandidates.first {
            $0.url.lastPathComponent == ".vscode"
        })
        XCTAssertEqual(vscode.category, .developer)
        XCTAssertEqual(vscode.risk, .sensitive)
        XCTAssertEqual(vscode.confidence, .high)
        XCTAssertEqual(vscode.ownership, .owned)

        let vscodeShared = try XCTUnwrap(vscodeCandidates.first {
            $0.url.lastPathComponent == ".vscode-shared"
        })
        XCTAssertEqual(vscodeShared.confidence, .medium)
        XCTAssertEqual(vscodeShared.ownership, .possible)

        let cursorCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.todesktop.230313mzl4w4u92",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        let cursor = try XCTUnwrap(cursorCandidates.first {
            $0.url.lastPathComponent == ".cursor"
        })
        XCTAssertEqual(cursor.category, .aiData)
        XCTAssertEqual(cursor.risk, .sensitive)
        XCTAssertEqual(cursor.confidence, .high)
        XCTAssertEqual(cursor.ownership, .owned)
    }

    func testBuiltInSharedServiceRulesNeverClaimExclusiveOwnership() throws {
        let fixture = try Fixture()
        let dockerCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.docker.docker",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        let dockerCLI = try XCTUnwrap(dockerCandidates.first {
            $0.ruleID == "product.docker.cli-data.v1"
        })
        XCTAssertEqual(dockerCLI.risk, .sensitive)
        XCTAssertEqual(dockerCLI.confidence, .medium)
        XCTAssertEqual(dockerCLI.ownership, .shared)

        let edgeCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.microsoft.edgemac",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
        let edgeUpdater = try XCTUnwrap(edgeCandidates.first {
            $0.ruleID == "service.microsoft.edge-updater.v1"
        })
        XCTAssertEqual(edgeUpdater.risk, .rebuildable)
        XCTAssertEqual(edgeUpdater.confidence, .medium)
        XCTAssertEqual(edgeUpdater.ownership, .shared)

        let jetBrainsCandidates = try ApplicationAssociationKnowledgeBase.builtInV1
            .candidates(
                for: fixture.context(
                    bundleIdentifier: "com.jetbrains.intellij.ce",
                    teamIdentifier: nil
                ),
                homeDirectory: fixture.home
            )
            .filter { $0.ruleID == "vendor.jetbrains.shared-data.v1" }
        XCTAssertEqual(jetBrainsCandidates.count, 3)
        XCTAssertTrue(jetBrainsCandidates.allSatisfy {
            $0.confidence == .medium
                && $0.ownership == .shared
                && $0.disposition == .inspectOnly
        })
    }

    private func knowledgeBase(
        path: String
    ) -> ApplicationAssociationKnowledgeBase {
        ApplicationAssociationKnowledgeBase(
            schemaVersion: 1,
            contentVersion: "test",
            rules: [
                ApplicationAssociationKnowledgeRule(
                    id: "test",
                    match: ApplicationAssociationKnowledgeMatch(
                        bundleIdentifiers: ["com.example.Editor"]
                    ),
                    paths: [
                        ApplicationAssociationPathRule(
                            scope: .homeDirectory,
                            template: path,
                            category: .cache,
                            risk: .rebuildable,
                            confidence: .high,
                            ownership: .owned
                        )
                    ]
                )
            ]
        )
    }

    private func rule(
        id: String = "test",
        match: ApplicationAssociationKnowledgeMatch = .init(
            bundleIdentifiers: ["com.example.Editor"]
        )
    ) -> ApplicationAssociationKnowledgeRule {
        ApplicationAssociationKnowledgeRule(
            id: id,
            match: match,
            paths: [
                ApplicationAssociationPathRule(
                    scope: .homeDirectory,
                    template: "Library/Caches/{bundleID}",
                    category: .cache,
                    risk: .rebuildable,
                    confidence: .high,
                    ownership: .owned
                )
            ]
        )
    }
}

private struct Fixture {
    let root: URL
    let home: URL
    let applicationBundle: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(
            path: "SpacePilot-Knowledge-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        home = root.appending(path: "Home", directoryHint: .isDirectory)
        applicationBundle = root.appending(
            path: "Applications/Editor.app",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: applicationBundle,
            withIntermediateDirectories: true
        )
    }

    func context(
        bundleIdentifier: String?,
        teamIdentifier: String?
    ) -> ApplicationAssociationKnowledgeContext {
        ApplicationAssociationKnowledgeContext(
            applicationName: "Editor",
            bundleIdentifier: bundleIdentifier,
            teamIdentifier: teamIdentifier,
            applicationBundleURL: applicationBundle
        )
    }
}
