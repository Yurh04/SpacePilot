import Foundation
@testable import SpacePilotCore

final class RecordingTrashMover: TrashMoving, @unchecked Sendable {
    private let lock = NSLock()
    private let failingAtIndex: Int?
    private(set) var movedURLs: [URL] = []

    init(failingAtIndex: Int? = nil) {
        self.failingAtIndex = failingAtIndex
    }

    func moveToTrash(_ url: URL) throws -> URL {
        try lock.withLock {
            let index = movedURLs.count
            if index == failingAtIndex {
                throw CocoaError(.fileWriteUnknown)
            }
            movedURLs.append(url)
            return URL(fileURLWithPath: "/Users/test/.Trash").appending(path: url.lastPathComponent)
        }
    }
}

final class FixtureTrashMover: TrashMoving, @unchecked Sendable {
    private let destination: URL

    init(destination: URL) throws {
        self.destination = destination
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func moveToTrash(_ url: URL) throws -> URL {
        let target = destination.appending(path: url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }
}
