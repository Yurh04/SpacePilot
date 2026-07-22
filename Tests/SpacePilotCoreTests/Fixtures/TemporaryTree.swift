import Foundation

final class TemporaryTree: @unchecked Sendable {
    let url: URL

    init(files: [String: Int]) throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for (relativePath, byteCount) in files {
            let fileURL = url.appending(path: relativePath)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(repeating: 0x41, count: byteCount).write(to: fileURL)
        }
    }

    deinit {
        let expectedPrefix = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotTests-")
            .path
        guard url.path.hasPrefix(expectedPrefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
