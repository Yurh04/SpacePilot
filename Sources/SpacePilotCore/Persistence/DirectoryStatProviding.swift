import Foundation

public protocol DirectoryStatProviding: Sendable {
    func cachedDirectoryStat(at url: URL) async throws -> DirectoryStat?
}

extension SQLiteIndexStore: DirectoryStatProviding {}
