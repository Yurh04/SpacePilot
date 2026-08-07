import Foundation

/// A pure, read-only join between the deep-scan AI applications (which already
/// have a rich `AIApplicationProjection`) and the applications discovered by the
/// `AIToolRegistry`. It surfaces registry applications that do **not** yet have a
/// deep projection so the UI can show them without duplicating the deep entries.
///
/// Matching is deterministic and never guesses by display name: a registry
/// application is considered already-covered when it shares a bundle identifier
/// (case-insensitive) or a standardized application URL with a deep application.
public enum AIApplicationJoin {
    /// A registry-discovered application that has no matching deep projection.
    public struct RegistryOnlyApplication: Identifiable, Sendable, Equatable {
        public let id: String
        public let displayName: String
        public let bundleIdentifier: String?
        public let applicationURL: URL?
        public let detectedVersion: String?
        public let coverageFailures: [AIToolCoverageFailure]

        public init(
            id: String,
            displayName: String,
            bundleIdentifier: String?,
            applicationURL: URL?,
            detectedVersion: String?,
            coverageFailures: [AIToolCoverageFailure]
        ) {
            self.id = id
            self.displayName = displayName
            self.bundleIdentifier = bundleIdentifier
            self.applicationURL = applicationURL
            self.detectedVersion = detectedVersion
            self.coverageFailures = coverageFailures
        }
    }

    /// Returns the registry applications not already represented by a deep
    /// application, ordered deterministically by display name then stable ID.
    ///
    /// Registry records are first ordered deterministically, then deduplicated
    /// against both the deep applications *and* each other by normalized bundle
    /// identifier / standardized (symlink-resolved) application URL — never by
    /// display name — so two registry records pointing at the same tool emit a
    /// single row.
    ///
    /// - Parameters:
    ///   - deepApplications: The deep-scan applications (identity source).
    ///   - registryApplications: `AIToolRecord`s of kind `.application`.
    public static func registryOnlyApplications(
        deepApplications: [AIApplicationRecord],
        registryApplications: [AIToolRecord]
    ) -> [RegistryOnlyApplication] {
        var coveredBundleIdentifiers = Set<String>()
        var coveredApplicationPaths = Set<String>()
        for application in deepApplications {
            if let bundleIdentifier = normalizedBundleIdentifier(application.bundleIdentifier) {
                coveredBundleIdentifiers.insert(bundleIdentifier)
            }
            if let path = normalizedPath(application.applicationURL) {
                coveredApplicationPaths.insert(path)
            }
        }

        // Order the registry input deterministically before deduplication so the
        // survivor of a bundle/path collision does not depend on input order.
        let orderedRecords = registryApplications
            .filter { $0.kind == .application }
            .sorted { lhs, rhs in
                let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
                if order != .orderedSame {
                    return order == .orderedAscending
                }
                return lhs.id < rhs.id
            }

        var results: [RegistryOnlyApplication] = []
        var emittedIDs = Set<String>()
        for record in orderedRecords {
            let bundleIdentifier = normalizedBundleIdentifier(record.evidence.bundleIdentifier)
            let path = normalizedPath(record.evidence.applicationURL)

            if let bundleIdentifier, coveredBundleIdentifiers.contains(bundleIdentifier) {
                continue
            }
            if let path, coveredApplicationPaths.contains(path) {
                continue
            }
            guard emittedIDs.insert(record.id).inserted else { continue }

            // Reserve this record's bundle/path so a later registry record that
            // resolves to the same tool is treated as a duplicate and skipped.
            if let bundleIdentifier {
                coveredBundleIdentifiers.insert(bundleIdentifier)
            }
            if let path {
                coveredApplicationPaths.insert(path)
            }

            results.append(RegistryOnlyApplication(
                id: record.id,
                displayName: record.displayName,
                bundleIdentifier: record.evidence.bundleIdentifier,
                applicationURL: record.evidence.applicationURL,
                detectedVersion: record.evidence.detectedVersion,
                coverageFailures: record.coverageFailures.sorted { $0.rawValue < $1.rawValue }
            ))
        }

        return results.sorted { lhs, rhs in
            let order = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if order != .orderedSame {
                return order == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    /// The union count of AI applications for the Overview page: every deep
    /// application plus the registry-only applications that survive the join. It
    /// counts each real tool exactly once, so a deep application whose registry
    /// discovery is still in flight (or failed) is never dropped to zero, and a
    /// tool present in both sources is never double counted.
    public static func applicationCount(
        deepApplications: [AIApplicationRecord],
        registryApplications: [AIToolRecord]
    ) -> Int {
        deepApplications.count + registryOnlyApplications(
            deepApplications: deepApplications,
            registryApplications: registryApplications
        ).count
    }

    private static func normalizedBundleIdentifier(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func normalizedPath(_ url: URL?) -> String? {
        guard let url else { return nil }
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
