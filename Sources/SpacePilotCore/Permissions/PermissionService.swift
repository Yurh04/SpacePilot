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

    @MainActor
    public func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
