import Foundation

/// Locates installed AI applications from an immutable `ScanSnapshot`, so that
/// discovery can resolve bundle identifiers to on-disk URLs without importing
/// AppKit or touching `NSWorkspace`.
///
/// The index is built once at initialization and never mutated. Resolution is
/// fully deterministic:
/// - AI application records that carry an explicit `applicationURL` take
///   priority over general application records.
/// - When a single bundle identifier maps to multiple candidate URLs, the
///   lexicographically smallest standardized path is chosen, so the result does
///   not depend on the ordering of the snapshot's arrays.
public struct SnapshotAIApplicationLocator: AIApplicationLocating {
    private let urlsByBundleID: [String: URL]

    public init(snapshot: ScanSnapshot) {
        var aiCandidates: [String: [URL]] = [:]
        for application in snapshot.aiApplications {
            guard let bundleID = application.bundleIdentifier,
                  let url = application.applicationURL else { continue }
            aiCandidates[bundleID, default: []].append(url)
        }

        var appCandidates: [String: [URL]] = [:]
        for application in snapshot.applications {
            guard let bundleID = application.bundleIdentifier else { continue }
            appCandidates[bundleID, default: []].append(application.url)
        }

        var map: [String: URL] = [:]
        let bundleIDs = Set(aiCandidates.keys).union(appCandidates.keys)
        for bundleID in bundleIDs {
            if let chosen = Self.deterministicPick(aiCandidates[bundleID]) {
                map[bundleID] = chosen
            } else if let chosen = Self.deterministicPick(appCandidates[bundleID]) {
                map[bundleID] = chosen
            }
        }
        urlsByBundleID = map
    }

    public func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL? {
        urlsByBundleID[bundleIdentifier]
    }

    /// Chooses a single deterministic URL from a set of candidates, preferring
    /// the lexicographically smallest standardized path so the pick is stable
    /// regardless of input order.
    private static func deterministicPick(_ urls: [URL]?) -> URL? {
        guard let urls, !urls.isEmpty else { return nil }
        return urls.min {
            $0.standardizedFileURL.path < $1.standardizedFileURL.path
        }
    }
}
