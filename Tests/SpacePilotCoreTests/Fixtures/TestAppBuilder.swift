import Foundation

enum TestAppBuilder {
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

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleShortVersionString": version,
            "CFBundleExecutable": name
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: contents.appending(path: "Info.plist"))
        try Data(repeating: 0x42, count: executableBytes).write(to: macOS.appending(path: name))
        return (tree, appURL)
    }
}
