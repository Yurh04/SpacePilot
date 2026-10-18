import Foundation

public enum ApplicationCacheCleanupPolicyError: Error, Equatable, LocalizedError, Sendable {
    case missingApplicationIdentity
    case protectedApplication(String)
    case invalidCacheLocation(String)

    public var errorDescription: String? {
        switch self {
        case .missingApplicationIdentity:
            "Application cache identity is missing"
        case .protectedApplication(let identifier):
            "Protected application cache: \(identifier)"
        case .invalidCacheLocation(let path):
            "Path is not an approved application cache root: \(path)"
        }
    }
}

/// A second, capability-specific gate for application cache cleanup.
/// Generic path safety is intentionally not enough: only the exact cache root
/// belonging to the recorded application bundle identifier is accepted.
public enum ApplicationCacheCleanupPolicy {
    public static let knownCacheRootsByBundleIdentifier: [String: Set<String>] = [
        "com.google.Chrome": ["Library/Caches/Google/Chrome"],
        "com.google.Chrome.canary": ["Library/Caches/Google/Chrome Canary"],
        "com.microsoft.edgemac": ["Library/Caches/Microsoft Edge"]
    ]

    private static let protectedIdentifierFragments = [
        "account", "appleid", "authkit", "authentication", "authorization",
        "identityservice", "icloud", "itunescloud", "keychain", "passkit",
        "screentime", "inputmethod", "1password", "agilebits", "bitwarden",
        "lastpass", "dashlane", "keepass", "authy", "yubico", "crowdstrike",
        "sentinelone", "sentinel-labs", "jamf", "paloaltonetworks",
        "cisco.anyconnect", "cisco.secureclient"
    ]

    public static func isProtected(bundleIdentifier: String) -> Bool {
        let identifier = bundleIdentifier.lowercased()
        if identifier.hasPrefix("com.apple.") || identifier.hasPrefix("group.com.apple.") {
            return true
        }
        return protectedIdentifierFragments.contains { identifier.contains($0) }
    }

    public static func validate(
        _ url: URL,
        homeDirectory: URL,
        bundleIdentifier: String?,
        approvedRelativePath: String? = nil
    ) throws {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            throw ApplicationCacheCleanupPolicyError.missingApplicationIdentity
        }
        guard !isProtected(bundleIdentifier: bundleIdentifier) else {
            throw ApplicationCacheCleanupPolicyError.protectedApplication(bundleIdentifier)
        }

        let home = homeDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = url.standardizedFileURL.resolvingSymlinksInPath()
        let directCache = home
            .appending(path: "Library/Caches", directoryHint: .isDirectory)
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let containerCache = home
            .appending(path: "Library/Containers", directoryHint: .isDirectory)
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "Data/Library/Caches", directoryHint: .isDirectory)
            .standardizedFileURL
            .resolvingSymlinksInPath()

        if let approvedRelativePath {
            guard isApprovedRelativePath(approvedRelativePath) else {
                throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
            }
            let components = NSString(string: approvedRelativePath).pathComponents
            if components.count == 3,
               components[0] == "Library", components[1] == "Caches",
               components[2] != bundleIdentifier {
                throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
            }
            if components.count > 3,
               components[0] == "Library", components[1] == "Caches",
               knownCacheRootsByBundleIdentifier[bundleIdentifier]?
                    .contains(approvedRelativePath) != true {
                throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
            }
            if components.count == 6,
               components[0] == "Library", components[1] == "Containers",
               components[2] != bundleIdentifier {
                throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
            }
            let approved = home
                .appending(path: approvedRelativePath, directoryHint: .isDirectory)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard candidate.path == approved.path else {
                throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
            }
            return
        }

        guard candidate.path == directCache.path || candidate.path == containerCache.path else {
            throw ApplicationCacheCleanupPolicyError.invalidCacheLocation(candidate.path)
        }
    }

    /// The scanner may approve exact application-support cache leaves, but not
    /// an application-support root or an arbitrary descendant supplied later.
    public static func isApprovedRelativePath(_ relativePath: String) -> Bool {
        let components = NSString(string: relativePath).pathComponents
        guard !relativePath.hasPrefix("/"), !components.contains("..") else {
            return false
        }
        if components.count >= 3,
           components[0] == "Library",
           components[1] == "Caches" {
            return true
        }
        if components.count == 6,
           components[0] == "Library",
           components[1] == "Containers",
           components[3] == "Data",
           components[4] == "Library",
           components[5] == "Caches" {
            return true
        }
        guard components.count >= 4,
              components[0] == "Library",
              components[1] == "Application Support" else {
            return false
        }
        let allowedLeafNames: Set<String> = [
            "Cache", "Code Cache", "GPUCache", "ShaderCache",
            "DawnWebGPUCache", "CachedData", "component_crx_cache"
        ]
        if let last = components.last, allowedLeafNames.contains(last) {
            return true
        }
        return components.suffix(2) == ["Crashpad", "completed"]
            || components.suffix(2) == ["Service Worker", "CacheStorage"]
            || components.suffix(2) == ["Service Worker", "ScriptCache"]
    }
}
