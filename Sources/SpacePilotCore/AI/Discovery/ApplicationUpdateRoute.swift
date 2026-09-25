import Foundation

/// Read-only desktop release metadata. Match bundle IDs, never display names.
/// A cask listing is NOT proof of a Homebrew installation; no execution route
/// is granted to applications. They continue to update through their own app.
public enum ApplicationUpdateRoute {
    public static func capability(bundleIdentifier: String?) -> UpdateCapability? {
        guard let bundleIdentifier, let token = casks[bundleIdentifier] else { return nil }
        return UpdateCapability(providerID: "homebrew-cask", providerKind: .homebrewCask,
                                packageIdentifier: token)
    }

    private static let casks: [String: String] = [
        "com.microsoft.VSCode": "visual-studio-code",
        "com.todesktop.230313mzl4w4u92": "cursor",
        "com.exafunction.windsurf": "windsurf",
        "com.google.antigravity": "antigravity",
        "com.electron.ollama": "ollama"
    ]
}
