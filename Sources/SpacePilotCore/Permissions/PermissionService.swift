import AppKit
import Foundation

public enum PermissionCoverage: Equatable, Sendable {
    case full
    case limited(deniedPaths: [URL])
    case unknown
}

public struct PermissionService: Sendable {
    public init() {}

    public func coverageStatus(deniedPaths: [URL]?) -> PermissionCoverage {
        guard let deniedPaths else { return .unknown }
        return deniedPaths.isEmpty ? .full : .limited(deniedPaths: deniedPaths)
    }

    /// Checks whether at least one path that failed during the previous scan is
    /// readable now. This is intentionally shallow: it detects a permission
    /// change without walking the user's home directory or reading file bodies.
    public func hasReadableCoverageChange(deniedPaths: [URL]) -> Bool {
        let fileManager = FileManager.default

        return deniedPaths.contains { url in
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return false
            }

            if isDirectory.boolValue {
                return (try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: []
                )) != nil
            }

            guard let handle = try? FileHandle(forReadingFrom: url) else {
                return false
            }
            try? handle.close()
            return true
        }
    }

    @MainActor
    public func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
