import Foundation

public enum PathSafetyError: Error, Equatable, LocalizedError, Sendable {
    case broadPath(String)
    case systemPath(String)
    case outsideAllowedVolume(String)

    public var errorDescription: String? {
        switch self {
        case .broadPath(let path): "Refusing broad path: \(path)"
        case .systemPath(let path): "Refusing protected system path: \(path)"
        case .outsideAllowedVolume(let path): "Path is outside the allowed internal volume: \(path)"
        }
    }
}

public struct PathSafetyPolicy: Sendable {
    public let homeDirectory: URL
    public let allowedVolumeRoot: URL

    public init(homeDirectory: URL, allowedVolumeRoot: URL) {
        self.homeDirectory = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.allowedVolumeRoot = allowedVolumeRoot.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func validate(_ url: URL) throws -> URL {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let path = canonical.path
        guard isContained(canonical, in: allowedVolumeRoot) else {
            throw PathSafetyError.outsideAllowedVolume(path)
        }

        let broadPaths: Set<String> = [
            allowedVolumeRoot.path,
            homeDirectory.path,
            "/Library",
            "/Applications",
            "/Users",
            "/Volumes"
        ]
        if broadPaths.contains(path) {
            throw PathSafetyError.broadPath(path)
        }

        if path == "/System" || path.hasPrefix("/System/") || path.hasPrefix("/Volumes/") {
            throw PathSafetyError.systemPath(path)
        }
        return canonical
    }

    private func isContained(_ child: URL, in root: URL) -> Bool {
        if root.path == "/" { return child.path.hasPrefix("/") }
        return child.path == root.path || child.path.hasPrefix(root.path + "/")
    }
}
