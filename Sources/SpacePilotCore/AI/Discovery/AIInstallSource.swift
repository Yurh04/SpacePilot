import Foundation

/// Infers how a discovered AI tool was installed from the location of its
/// executable. This is display-only evidence: the path is never executed and
/// nothing is trusted from it beyond a well-known prefix match. Kept in Core so
/// both the CLI Tools list and the Other AI Tools projection classify the same
/// way on any machine, with no hardcoded per-tool or per-user paths.
public enum AIInstallSource: String, Sendable {
    case homebrew
    case npm
    case pipx
    case local
    case unknown

    /// Classifies an executable URL. Order matters: the most specific manager
    /// layout wins before the broad Homebrew/usr-local prefixes.
    public static func classify(executableURL: URL?) -> AIInstallSource {
        guard let path = executableURL?.path, !path.isEmpty else { return .unknown }
        if path.contains("/pipx/") || path.contains("/.local/pipx/") { return .pipx }
        if path.contains("/node_modules/") || path.contains("/pnpm/")
            || path.contains("/fnm/") || path.contains("/.nvm/") { return .npm }
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/") { return .homebrew }
        if path.contains("/.local/bin/") || path.contains("/.local/share/") { return .local }
        return .unknown
    }

    /// The `OtherAIToolInstallMethod` this source maps to, so the Other AI Tools
    /// list and the CLI list agree on install-method semantics.
    public var otherToolInstallMethod: OtherAIToolInstallMethod {
        switch self {
        case .homebrew: return .homebrew
        case .npm: return .npm
        case .pipx: return .pipx
        case .local, .unknown: return .unknown
        }
    }
}
