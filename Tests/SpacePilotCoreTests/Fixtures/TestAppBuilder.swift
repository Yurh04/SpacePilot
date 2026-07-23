import Foundation
@testable import SpacePilotCore

struct TestAppBuilder {
    private struct EmbeddedBundle {
        let relativePath: String
        let bundleIdentifier: String
    }

    private let name: String
    private let bundleIdentifier: String
    private var embeddedBundles: [EmbeddedBundle] = []

    init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    func withEmbeddedBundle(
        relativePath: String,
        bundleIdentifier: String
    ) -> Self {
        var copy = self
        copy.embeddedBundles.append(
            EmbeddedBundle(
                relativePath: relativePath,
                bundleIdentifier: bundleIdentifier
            )
        )
        return copy
    }

    func build() throws -> TestAppFixture {
        let fixture = try Self.make(
            name: name,
            bundleID: bundleIdentifier,
            version: "1.0",
            executableBytes: 16
        )

        for embeddedBundle in embeddedBundles {
            let bundleURL = fixture.appURL.appending(
                path: embeddedBundle.relativePath,
                directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(
                at: bundleURL,
                withIntermediateDirectories: true
            )
            try Self.writeInfoPlist(
                bundleIdentifier: embeddedBundle.bundleIdentifier,
                name: bundleURL.deletingPathExtension().lastPathComponent,
                to: bundleURL.appending(path: "Contents/Info.plist")
            )
        }

        return TestAppFixture(
            tree: fixture.tree,
            record: ApplicationRecord(
                name: name,
                bundleIdentifier: bundleIdentifier,
                version: "1.0",
                url: fixture.appURL,
                executableURL: fixture.appURL.appending(path: "Contents/MacOS/\(name)"),
                allocatedSize: 16
            )
        )
    }

    static func make(
        in root: URL? = nil,
        name: String,
        bundleID: String,
        version: String,
        executableBytes: Int
    ) throws -> (tree: TemporaryTree, appURL: URL) {
        let tree = try TemporaryTree(files: [:])
        let parent = root ?? tree.url
        let appURL = parent.appending(path: "\(name).app", directoryHint: .isDirectory)
        let contents = appURL.appending(path: "Contents", directoryHint: .isDirectory)
        let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)

        try writeInfoPlist(
            bundleIdentifier: bundleID,
            name: name,
            version: version,
            executable: name,
            to: contents.appending(path: "Info.plist")
        )
        try Data(repeating: 0x42, count: executableBytes).write(to: macOS.appending(path: name))
        return (tree, appURL)
    }

    private static func writeInfoPlist(
        bundleIdentifier: String,
        name: String,
        version: String? = nil,
        executable: String? = nil,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleName": name
        ]
        plist["CFBundleShortVersionString"] = version
        plist["CFBundleExecutable"] = executable
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: url)
    }
}

struct TestAppFixture {
    let tree: TemporaryTree
    let record: ApplicationRecord
}
