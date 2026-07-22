import Foundation

public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) throws -> URL
}

public struct FileManagerTrashMover: TrashMoving {
    public init() {}

    public func moveToTrash(_ url: URL) throws -> URL {
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return (resultingURL as URL?) ?? url
    }
}
