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
