import Foundation
@testable import SpacePilotCore

final class EdgeAssociationFixture: @unchecked Sendable {
    let tree: TemporaryTree
    let application: ApplicationRecord
    let identity: ApplicationIdentity
    let launchAgentURL: URL
    let updaterSupportURL: URL

    private init(
        tree: TemporaryTree,
        application: ApplicationRecord,
        identity: ApplicationIdentity,
        launchAgentURL: URL,
        updaterSupportURL: URL
    ) {
        self.tree = tree
        self.application = application
        self.identity = identity
        self.launchAgentURL = launchAgentURL
        self.updaterSupportURL = updaterSupportURL
    }

    static func make() throws -> EdgeAssociationFixture {
        let tree = try TemporaryTree(files: [
            "Library/Application Support/com.microsoft.edgemac/state.db": 11,
            "Library/Caches/com.microsoft.edgemac/cache.bin": 12,
            "Library/Preferences/com.microsoft.edgemac.plist": 13,
            "Library/HTTPStorages/com.microsoft.edgemac/http.db": 14,
            "Library/WebKit/com.microsoft.edgemac/WebsiteData/data.db": 15,
            "Library/Application Support/CrashReporter/com.microsoft.edgemac/crash.log": 16,
            "Library/Logs/DiagnosticReports/com.microsoft.edgemac/report.diag": 17,
            "Library/Containers/com.microsoft.edgemac.wdgExtension/state.db": 18,
            "Library/Application Scripts/com.microsoft.edgemac.wdgExtension/script.scpt": 19,
            "Library/Group Containers/UBF8T346G9.com.microsoft.oneauth/token.db": 20,
            "Library/Group Containers/UBF8T346G9.com.microsoft.entrabroker/token.db": 21,
            "Library/Application Support/Microsoft/EdgeUpdater/EdgeUpdater.app/Contents/MacOS/EdgeUpdater": 22,
            "Library/Application Support/Microsoft/UnrelatedService/state.db": 23
        ])
        let application = ApplicationRecord(
            name: "Microsoft Edge",
            bundleIdentifier: "com.microsoft.edgemac",
            version: "1.0",
            url: URL(fileURLWithPath: "/Applications/Microsoft Edge.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let identity = ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: ["com.microsoft.edgemac.wdgExtension"],
            teamIdentifier: "UBF8T346G9",
            applicationGroups: [
                "UBF8T346G9.com.microsoft.oneauth",
                "UBF8T346G9.com.microsoft.entrabroker"
            ]
        )
        let launchAgentURL = tree.url.appending(
            path: "Library/LaunchAgents/com.microsoft.update.agent.plist"
        )
        let updaterSupportURL = tree.url.appending(
            path: "Library/Application Support/Microsoft/EdgeUpdater",
            directoryHint: .isDirectory
        )
        try writeLaunchAgent(
            at: launchAgentURL,
            target: updaterSupportURL.appending(
                path: "EdgeUpdater.app/Contents/MacOS/EdgeUpdater"
            )
        )
        return EdgeAssociationFixture(
            tree: tree,
            application: application,
            identity: identity,
            launchAgentURL: launchAgentURL,
            updaterSupportURL: updaterSupportURL
        )
    }

    static func writeLaunchAgent(at url: URL, target: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try PropertyListSerialization.data(
            fromPropertyList: [
                "Label": "fixture.launch-agent",
                "ProgramArguments": [target.path, "--wake"]
            ],
            format: .xml,
            options: 0
        )
        try data.write(to: url)
    }
}
