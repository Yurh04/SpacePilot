import Foundation

public struct SpacePilotRuntime: Sendable {
    public let homeDirectory: URL
    public let store: SQLiteIndexStore
    public let coordinator: ScanCoordinator

    public init(homeDirectory: URL, store: SQLiteIndexStore, coordinator: ScanCoordinator) {
        self.homeDirectory = homeDirectory
        self.store = store
        self.coordinator = coordinator
    }

    public static func live() throws -> SpacePilotRuntime {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let databaseURL = home.appending(path: "Library/Application Support/SpacePilot/index.sqlite")
        let store = try SQLiteIndexStore(url: databaseURL)
        return SpacePilotRuntime(
            homeDirectory: home,
            store: store,
            coordinator: ScanCoordinator(homeDirectory: home, store: store)
        )
    }
}
