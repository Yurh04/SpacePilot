import Foundation

/// Pure, read-only classification of a user's multi-selection for the update
/// flow. It contains NO commands, provider endpoints, or executable plans — it
/// only groups the selected assets by whether they can be checked/updated and,
/// when a prior check result exists, by their update status. 5B consumes this
/// to build a user-confirmed execution plan; 5A only displays it.
///
/// Ordering is deterministic (assets sorted by their stable `AIUpdateAssetKey`)
/// so the same selection always yields the same plan regardless of input order.
public struct AIUpdateSelectionPlan: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public let key: AIUpdateAssetKey
        public let displayName: String
        /// True when a fixed, code-owned update provider capability exists. When
        /// false the asset can never be checked or updated (official handoff).
        public let isSupported: Bool
        public let status: UpdateStatus
        public let currentVersion: String?
        public let latestVersion: String?

        public var id: AIUpdateAssetKey { key }

        public init(
            key: AIUpdateAssetKey,
            displayName: String,
            isSupported: Bool,
            status: UpdateStatus,
            currentVersion: String?,
            latestVersion: String?
        ) {
            self.key = key
            self.displayName = displayName
            self.isSupported = isSupported
            self.status = status
            self.currentVersion = currentVersion
            self.latestVersion = latestVersion
        }
    }

    /// A currently-visible, selected row. Because it comes from a rendered row it
    /// always carries a stable key and a display name, so the plan can build a
    /// complete entry (a placeholder unsupported entry when no updatable asset
    /// exists) instead of silently dropping the selection. This is what keeps the
    /// action-bar buttons responsive for any visible selection.
    public struct SelectedRow: Equatable, Sendable {
        public let key: AIUpdateAssetKey
        public let displayName: String

        public init(key: AIUpdateAssetKey, displayName: String) {
            self.key = key
            self.displayName = displayName
        }
    }

    /// Every selected asset that is a known updatable asset, deterministic order.
    public let selected: [Entry]
    /// Selected assets that have a fixed update provider capability.
    public let supported: [Entry]
    /// Selected assets with no trusted provider — cannot be updated here.
    public let unsupported: [Entry]
    /// Supported assets whose last check reported an available update.
    public let updateAvailable: [Entry]
    /// Supported assets whose last check reported they are already current.
    public let alreadyLatest: [Entry]
    /// Selected assets whose local version evidence conflicts (no single truth).
    public let conflict: [Entry]

    public init(
        selectedKeys: Set<AIUpdateAssetKey>,
        assets: [AIUpdateAsset],
        results: [AIUpdateAssetKey: UpdateCheckResult]
    ) {
        let assetByKey = Dictionary(assets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = selectedKeys
            .compactMap { key -> Entry? in
                guard let asset = assetByKey[key] else { return nil }
                let result = results[key]
                let isSupported = asset.capability != nil
                let status = Self.status(asset: asset, result: result, isSupported: isSupported)
                return Entry(
                    key: key,
                    displayName: asset.displayName,
                    isSupported: isSupported,
                    status: status,
                    currentVersion: asset.localVersion.selectedVersion,
                    latestVersion: result?.latestVersion
                )
            }
            .sorted { $0.key < $1.key }
        self.init(entries: entries, assetByKey: assetByKey)
    }

    /// Descriptor-based initializer used by the UI. Every visible selected row
    /// produces an entry: when a matching updatable asset exists it carries the
    /// asset's capability/version/status; otherwise it becomes a placeholder
    /// `unsupported` entry (using the row's own display name) so a selection of
    /// only unsupported rows still yields a non-empty, actionable plan.
    public init(
        selection: [SelectedRow],
        assets: [AIUpdateAsset],
        results: [AIUpdateAssetKey: UpdateCheckResult]
    ) {
        let assetByKey = Dictionary(assets.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        // De-duplicate rows that resolve to the same stable key (for example an
        // alias and its canonical executable), keeping the first display name.
        var seen = Set<AIUpdateAssetKey>()
        let entries = selection
            .compactMap { row -> Entry? in
                guard seen.insert(row.key).inserted else { return nil }
                if let asset = assetByKey[row.key] {
                    let result = results[row.key]
                    let isSupported = asset.capability != nil
                    let status = Self.status(asset: asset, result: result, isSupported: isSupported)
                    return Entry(
                        key: row.key,
                        displayName: asset.displayName,
                        isSupported: isSupported,
                        status: status,
                        currentVersion: asset.localVersion.selectedVersion,
                        latestVersion: result?.latestVersion
                    )
                }
                // No updatable asset for this visible row: placeholder unsupported
                // entry. Never dropped, so the buttons stay responsive.
                return Entry(
                    key: row.key,
                    displayName: row.displayName,
                    isSupported: false,
                    status: .unsupported,
                    currentVersion: nil,
                    latestVersion: nil
                )
            }
            .sorted { $0.key < $1.key }
        self.init(entries: entries, assetByKey: assetByKey)
    }

    private init(entries: [Entry], assetByKey: [AIUpdateAssetKey: AIUpdateAsset]) {
        selected = entries
        supported = entries.filter(\.isSupported)
        unsupported = entries.filter { !$0.isSupported }
        updateAvailable = entries.filter { $0.isSupported && $0.status == .updateAvailable }
        alreadyLatest = entries.filter { $0.isSupported && $0.status == .upToDate }
        conflict = entries.filter { if case .conflict = assetByKey[$0.key]?.localVersion { true } else { false } }
    }

    /// True when the user has any visible row selected. The action bar enables
    /// its buttons on this (not on `checkableKeys`) so unsupported-only selections
    /// still open a preflight/confirmation instead of leaving the button dead.
    public var hasSelection: Bool { !selected.isEmpty }

    /// The stable keys that a "check selected" action should request. Only
    /// supported assets are checkable; unsupported keys never produce a request.
    public var checkableKeys: [AIUpdateAssetKey] {
        supported.map(\.key)
    }

    private static func status(
        asset: AIUpdateAsset,
        result: UpdateCheckResult?,
        isSupported: Bool
    ) -> UpdateStatus {
        if let result { return result.status }
        return isSupported ? .unknown : .unsupported
    }
}
