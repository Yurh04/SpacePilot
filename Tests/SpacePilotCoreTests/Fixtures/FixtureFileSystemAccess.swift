import Foundation
@testable import SpacePilotCore

struct FixtureFileSystemAccess: FileSystemAccess {
    let base = LocalFileSystemAccess()
    let unreadable: Set<URL>

    init(unreadable: [URL]) {
        self.unreadable = Set(unreadable.map { $0.standardizedFileURL })
    }

    func metadata(at url: URL) throws -> FileMetadata {
        try base.metadata(at: url)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        if unreadable.contains(url.standardizedFileURL) {
            throw CocoaError(.fileReadNoPermission)
        }
        return try base.contentsOfDirectory(at: url)
    }
}
