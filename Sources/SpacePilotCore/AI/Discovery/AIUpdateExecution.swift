import Foundation

/// The package manager that a fixed, code-owned execution capability drives.
/// Only managers we can invoke as a single verified executable with fixed
/// arguments are represented; there is deliberately no "shell" or "custom"
/// case, so an execution can never originate from manifest/receipt data.
public enum UpdateExecutionManager: String, Codable, Hashable, Sendable {
    case npm
    case pnpm
    case pipx
    case uv
    case homebrew
    case claudeNative

    /// The version scheme a manager's packages are published under. `pipx`
    /// installs PyPI packages (PEP 440); the node managers install npm packages
    /// (SemVer). Used to validate a target version and to compare the re-probed
    /// installed version after an install.
    public var versionComparator: VersionComparatorKind {
        switch self {
        case .npm, .pnpm, .homebrew, .claudeNative: return .semver
        case .pipx, .uv: return .pep440
        }
    }
}

/// A fixed, code-owned authorization to *execute* an update for a tool. Unlike
/// `UpdateCapability` (which only reads the latest version over HTTPS), this
/// says "the latest version may be installed by running <manager> against
/// <packageIdentifier>". Every field is a code constant sourced from the known
/// definition table; nothing here is ever read from a manifest, receipt,
/// config, or PATH. The concrete manager executable path and argument template
/// are resolved by the executor from these constants alone.
public struct UpdateExecutionCapability: Hashable, Sendable {
    public let manager: UpdateExecutionManager
    /// The published package identifier the manager installs (for example
    /// `@openai/codex`, `aider-chat`). Must match the check capability's
    /// package identifier so the version that was checked is the one installed.
    public let packageIdentifier: String
    /// The discovered executable being updated, not a different global install.
    public let installationURL: URL?

    public init(manager: UpdateExecutionManager, packageIdentifier: String, installationURL: URL? = nil) {
        self.manager = manager
        self.packageIdentifier = packageIdentifier
        self.installationURL = installationURL
    }
}

/// Why a selected asset cannot enter the executable portion of an update plan.
public enum UpdateExecutionSkipReason: String, Codable, Hashable, Sendable {
    /// No fixed execution capability exists for this asset (handoff only).
    case unsupported
    /// A provider can read the latest version but no safe execution path exists.
    case checkOnly
    /// The asset was never checked, so there is no verified target version.
    case notChecked
    /// The last check reported the asset is already current.
    case alreadyLatest
    /// The last check could not determine a version (unknown/conflict/failed).
    case noTargetVersion
    /// The latest version string did not pass version validation.
    case invalidTargetVersion
}

/// A single, fully-resolved, user-confirmable update step. It carries the exact
/// verified manager executable and the exact argument list that will be run —
/// both derived only from code constants plus a validated latest version — so
/// the executor never has to interpret anything further. Non-executable
/// selections become `skipped` items instead, each with an honest reason.
public struct UpdateExecutionPlan: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let key: AIUpdateAssetKey
        public let displayName: String
        public let manager: UpdateExecutionManager
        public let packageIdentifier: String
        public let currentVersion: String?
        public let targetVersion: String
        /// The verified, absolute manager executable to run. Resolved by the
        /// executor at run time; the plan itself does not need it, but tests and
        /// the confirmation UI can display which manager will be used.
        public let managerDisplayName: String
        public let installationURL: URL?

        public var id: AIUpdateAssetKey { key }

        public init(
            key: AIUpdateAssetKey,
            displayName: String,
            manager: UpdateExecutionManager,
            packageIdentifier: String,
            currentVersion: String?,
            targetVersion: String,
            managerDisplayName: String,
            installationURL: URL? = nil
        ) {
            self.key = key
            self.displayName = displayName
            self.manager = manager
            self.packageIdentifier = packageIdentifier
            self.currentVersion = currentVersion
            self.targetVersion = targetVersion
            self.managerDisplayName = managerDisplayName
            self.installationURL = installationURL
        }
    }

    public struct SkippedItem: Equatable, Sendable, Identifiable {
        public let key: AIUpdateAssetKey
        public let displayName: String
        public let reason: UpdateExecutionSkipReason

        public var id: AIUpdateAssetKey { key }

        public init(key: AIUpdateAssetKey, displayName: String, reason: UpdateExecutionSkipReason) {
            self.key = key
            self.displayName = displayName
            self.reason = reason
        }
    }

    /// Items that will actually be executed, deterministic order, de-duplicated
    /// by package identifier so the same package is only installed once.
    public let executable: [Item]
    /// Selected items that will not run, each with an honest reason.
    public let skipped: [SkippedItem]

    /// True when at least one selection resolved to an executable step.
    public var hasExecutable: Bool { !executable.isEmpty }

    public init(executable: [Item], skipped: [SkippedItem]) {
        self.executable = executable
        self.skipped = skipped
    }

    /// Builds a plan from the user's selected assets and the last check results.
    /// Only assets whose last check reported `.updateAvailable`, that carry an
    /// execution capability, and whose latest version passes SemVer validation
    /// enter `executable`; everything else is `skipped` with a reason. Executable
    /// items are de-duplicated by `(manager, packageIdentifier)` so an alias and
    /// its canonical executable never install twice.
    public init(
        selectedKeys: Set<AIUpdateAssetKey>,
        assets: [AIUpdateAsset],
        executionCapabilities: [AIUpdateAssetKey: UpdateExecutionCapability],
        results: [AIUpdateAssetKey: UpdateCheckResult]
    ) {
        let assetByKey = Dictionary(assets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var executable: [Item] = []
        var skipped: [SkippedItem] = []
        var seenPackages = Set<String>()

        for key in selectedKeys.sorted() {
            guard let asset = assetByKey[key] else {
                // A visible selection with no updatable asset is unsupported.
                skipped.append(SkippedItem(key: key, displayName: key.canonicalLocation, reason: .unsupported))
                continue
            }
            guard let execution = executionCapabilities[key] else {
                let reason: UpdateExecutionSkipReason = asset.capability == nil ? .unsupported : .checkOnly
                skipped.append(SkippedItem(key: key, displayName: asset.displayName, reason: reason))
                continue
            }
            guard let result = results[key] else {
                skipped.append(SkippedItem(key: key, displayName: asset.displayName, reason: .notChecked))
                continue
            }
            switch result.status {
            case .updateAvailable:
                break
            case .upToDate:
                skipped.append(SkippedItem(key: key, displayName: asset.displayName, reason: .alreadyLatest))
                continue
            default:
                skipped.append(SkippedItem(key: key, displayName: asset.displayName, reason: .noTargetVersion))
                continue
            }
            let comparator = asset.capability?.comparator ?? execution.manager.versionComparator
            guard let latest = result.latestVersion,
                  VersionComparator.isValid(latest, kind: comparator) else {
                skipped.append(SkippedItem(key: key, displayName: asset.displayName, reason: .invalidTargetVersion))
                continue
            }
            let packageKey = "\(execution.manager.rawValue):\(execution.packageIdentifier):\(execution.installationURL?.path ?? "")"
            guard seenPackages.insert(packageKey).inserted else { continue }
            executable.append(Item(
                key: key,
                displayName: asset.displayName,
                manager: execution.manager,
                packageIdentifier: execution.packageIdentifier,
                currentVersion: asset.localVersion.selectedVersion,
                targetVersion: latest,
                managerDisplayName: execution.manager.rawValue,
                installationURL: execution.installationURL
            ))
        }

        self.executable = executable.sorted { $0.key < $1.key }
        self.skipped = skipped.sorted { $0.key < $1.key }
    }
}
