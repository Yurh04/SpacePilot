import Foundation

/// A flat, deterministic sidebar entry for the AI Apps section. The list is
/// rendered with **no** `Section`/header rows so that `NSTableView.clickedRow`
/// maps 1:1 to this array — the native double-click adapter can therefore rely
/// on `entries[row].revealURL` for both deep and registry-only applications.
///
/// "Discovered" (registry-only) status is expressed by `kind`, not by a
/// separate header row, precisely so the row indices stay stable.
public struct AIAppsSidebarEntry: Identifiable, Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// A deep-scan application; `deepID` is its `AIApplicationProjection` id.
        case deep(deepID: UUID)
        /// A registry-only application; `registryID` is the stable record id.
        case registry(registryID: String)
    }

    /// Stable, unique selection identifier (prefixed by kind to avoid collisions
    /// between a UUID string and a registry record id).
    public let id: String
    public let kind: Kind
    public let displayName: String
    public let subtitle: String?
    /// Whether this entry was surfaced only by the registry (no deep scan yet).
    public let isDiscovered: Bool
    /// The URL a double-click should reveal in Finder, or `nil` when unknown.
    public let revealURL: URL?

    public init(
        id: String,
        kind: Kind,
        displayName: String,
        subtitle: String?,
        isDiscovered: Bool,
        revealURL: URL?
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.subtitle = subtitle
        self.isDiscovered = isDiscovered
        self.revealURL = revealURL
    }
}

public enum AIAppsSidebar {
    /// Builds the flat entry list: deep applications first (in their given,
    /// already-deterministic order), then registry-only applications (already
    /// deterministically ordered by the join). Row order is stable and contains
    /// no header rows, so `entries[row]` is a valid mapping for the native
    /// double-click adapter.
    public static func entries(
        deepApplications: [DeepApplication],
        registryOnlyApplications: [AIApplicationJoin.RegistryOnlyApplication]
    ) -> [AIAppsSidebarEntry] {
        var entries: [AIAppsSidebarEntry] = []
        entries.reserveCapacity(deepApplications.count + registryOnlyApplications.count)

        for application in deepApplications {
            entries.append(AIAppsSidebarEntry(
                id: "deep:\(application.id.uuidString)",
                kind: .deep(deepID: application.id),
                displayName: application.displayName,
                subtitle: application.subtitle,
                isDiscovered: false,
                revealURL: application.revealURL
            ))
        }

        for discovered in registryOnlyApplications {
            entries.append(AIAppsSidebarEntry(
                id: "registry:\(discovered.id)",
                kind: .registry(registryID: discovered.id),
                displayName: discovered.displayName,
                subtitle: discovered.detectedVersion,
                isDiscovered: true,
                revealURL: discovered.applicationURL
            ))
        }

        return entries
    }

    /// Resolves which entry should be selected, preferring to preserve an
    /// existing selection over defaulting to the first row.
    ///
    /// Preference order:
    /// 1. The current `selectedEntryID` if it still identifies a present entry.
    /// 2. The deep entry matching `preferredDeepID` (the model's existing
    ///    `selectedAIApplicationID`) if it still exists — this restores the
    ///    prior deep-app selection instead of clobbering it with the first row.
    /// 3. The first entry.
    /// 4. `nil` when there are no entries.
    public static func resolvedSelection(
        entries: [AIAppsSidebarEntry],
        currentSelectionID: String?,
        preferredDeepID: UUID?
    ) -> String? {
        if let currentSelectionID,
           entries.contains(where: { $0.id == currentSelectionID }) {
            return currentSelectionID
        }
        if let preferredDeepID,
           let match = entries.first(where: { $0.kind == .deep(deepID: preferredDeepID) }) {
            return match.id
        }
        return entries.first?.id
    }

    /// Minimal, view-agnostic description of a deep application row so the entry
    /// builder stays a pure, testable function without importing SwiftUI.
    public struct DeepApplication: Sendable, Equatable {
        public let id: UUID
        public let displayName: String
        public let subtitle: String?
        public let revealURL: URL?

        public init(id: UUID, displayName: String, subtitle: String?, revealURL: URL?) {
            self.id = id
            self.displayName = displayName
            self.subtitle = subtitle
            self.revealURL = revealURL
        }
    }
}
