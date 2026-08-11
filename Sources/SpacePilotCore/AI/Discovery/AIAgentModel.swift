import Foundation

/// Where an AI Agent runs and is managed from the user's perspective.
///
/// - `local`: the machine hosts an Agent runtime/client that operates on the
///   local workspace (a local app bundle and/or a controlled local executable).
///   This does NOT assert that model inference happens locally — only that there
///   is a local Agent surface to manage.
/// - `remote`: the Agent is a cloud/remote service; the local footprint is at
///   most an account/client/config. It generally has no local storage, skills,
///   or plugins to manage.
///
/// Locality is a fixed, code-owned definition constant. It is never inferred
/// from "does a local executable exist"; `traex` is always `.remote`, `aiden`
/// is always `.local`.
public enum AIAgentLocality: String, Codable, Hashable, Sendable {
    case local
    case remote
}

/// The concrete surfaces through which a single Agent can appear. One Agent may
/// expose several form factors (for example an application plus a CLI); they are
/// merged into one Agent identity rather than shown as competing products.
public enum AIAgentFormFactor: String, Codable, Hashable, Sendable {
    case application
    case cli
    case cloud
}

/// A pure, AppKit-free description of where an Agent's icon should come from.
/// The Core layer only expresses intent and precedence; the App layer resolves
/// the actual image (for example via `NSWorkspace.icon(forFile:)`) and caches
/// it. Nothing here loads an image, touches the network, or reads a URL from a
/// manifest — `bundledAsset` and `systemSymbol` names are code constants and
/// `installedApplication` is a real, already-located application URL.
public enum AgentIconDescriptor: Hashable, Sendable {
    /// Highest precedence: the real, installed application bundle URL. The App
    /// layer reads the native file icon from this URL.
    case installedApplication(URL)
    /// A code-owned, bundled asset name shipped inside the app. Never sourced
    /// from data.
    case bundledAsset(name: String)
    /// Lowest precedence: an SF Symbol fallback name.
    case systemSymbol(name: String)

    /// Deterministic precedence used when picking a single icon for an Agent
    /// from several candidates: installed application > bundled asset > symbol.
    public var precedence: Int {
        switch self {
        case .installedApplication: return 0
        case .bundledAsset: return 1
        case .systemSymbol: return 2
        }
    }

    /// Resolves the best icon from a set of candidates, preferring the lowest
    /// precedence value. Ties break deterministically on the associated name/path
    /// so ordering of the input never changes the result.
    public static func resolve(from candidates: [AgentIconDescriptor]) -> AgentIconDescriptor? {
        candidates.min(by: Self.isOrderedBefore)
    }

    static func isOrderedBefore(_ lhs: AgentIconDescriptor, _ rhs: AgentIconDescriptor) -> Bool {
        if lhs.precedence != rhs.precedence { return lhs.precedence < rhs.precedence }
        return lhs.tieBreakKey < rhs.tieBreakKey
    }

    private var tieBreakKey: String {
        switch self {
        case .installedApplication(let url): return url.standardizedFileURL.path
        case .bundledAsset(let name): return name
        case .systemSymbol(let name): return name
        }
    }
}

/// A fixed, code-owned classification marking a definition as an AI Agent and
/// describing how it should be presented. A definition WITHOUT an
/// `AIAgentProfile` is not an Agent: it is a supporting developer CLI (for
/// example `bytedcli`, `merlin-cli`, `lark-cli`) and only ever appears in the
/// CLI Tools list.
public struct AIAgentProfile: Hashable, Sendable {
    public let locality: AIAgentLocality
    /// The surfaces this Agent may expose. Presence here is a capability
    /// declaration, not proof of installation; detection still requires real
    /// evidence for each form factor.
    public let formFactors: Set<AIAgentFormFactor>
    /// A code-owned fallback symbol used when no installed application icon is
    /// available (for example for CLI-only or remote Agents).
    public let fallbackSymbolName: String
    /// An optional code-owned bundled asset name (used ahead of the symbol when
    /// present, behind a real installed-application icon).
    public let bundledAssetName: String?

    public init(
        locality: AIAgentLocality,
        formFactors: Set<AIAgentFormFactor>,
        fallbackSymbolName: String,
        bundledAssetName: String? = nil
    ) {
        self.locality = locality
        self.formFactors = formFactors
        self.fallbackSymbolName = fallbackSymbolName
        self.bundledAssetName = bundledAssetName
    }
}
