import Foundation

public enum DeveloperStorageCleanupPolicyError: Error, Equatable, LocalizedError, Sendable {
    case missingApprovedPath
    case unrecognizedPath(String)

    public var errorDescription: String? {
        switch self {
        case .missingApprovedPath:
            "Developer storage cleanup path is missing"
        case .unrecognizedPath(let path):
            "Path is not an approved developer cache: \(path)"
        }
    }
}

/// Capability-specific cleanup gate for rebuildable developer-tool storage.
/// It deliberately excludes archives, simulator device data and project output.
public enum DeveloperStorageCleanupPolicy {
    public static let approvedRelativePaths: Set<String> = [
        "Library/Developer/Xcode/DerivedData",
        "Library/Developer/Xcode/iOS DeviceSupport",
        "Library/Developer/Xcode/watchOS DeviceSupport",
        "Library/Developer/Xcode/tvOS DeviceSupport",
        "Library/Developer/Xcode/visionOS DeviceSupport",
        "Library/Developer/Xcode/xrOS DeviceSupport",
        "Library/Developer/Xcode/DocumentationCache",
        "Library/Caches/com.apple.dt.Xcode",
        "Library/Caches/Homebrew",
        ".npm/_cacache",
        ".npm/_npx",
        ".npm/_logs",
        "Library/pnpm/store",
        ".local/share/pnpm/store",
        "Library/Caches/Yarn",
        ".cache/yarn",
        ".gradle/caches",
        ".gradle/wrapper/dists",
        ".m2/repository",
        ".cache/pip",
        "Library/Caches/pip",
        "Library/Caches/ms-playwright",
        ".cache/ms-playwright",
        "Library/Caches/puppeteer",
        ".cache/puppeteer",
        "Library/Caches/CocoaPods",
        ".cocoapods/repos",
        "Library/Caches/org.swift.swiftpm",
        ".swiftpm/cache",
        ".cargo/registry/cache",
        ".cargo/git/checkouts",
        "Library/Caches/go-build",
        "go/pkg/mod/cache",
        ".cache/deno",
        ".bun/install/cache"
    ]

    public static func validate(
        _ url: URL,
        homeDirectory: URL,
        approvedRelativePath: String?
    ) throws {
        guard let approvedRelativePath else {
            throw DeveloperStorageCleanupPolicyError.missingApprovedPath
        }
        guard approvedRelativePaths.contains(approvedRelativePath) else {
            throw DeveloperStorageCleanupPolicyError.unrecognizedPath(url.path)
        }
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let approved = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
            .appending(path: approvedRelativePath, directoryHint: .isDirectory)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == approved.path else {
            throw DeveloperStorageCleanupPolicyError.unrecognizedPath(candidate.path)
        }
    }
}
