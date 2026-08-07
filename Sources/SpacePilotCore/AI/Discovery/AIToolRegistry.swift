import Foundation

/// Read-only application presence lookup, injected so discovery is deterministic
/// in tests and never touches `NSWorkspace` directly from core.
public protocol AIApplicationLocating: Sendable {
    /// Returns the on-disk URL of an installed application for a bundle
    /// identifier, or `nil` if it is not installed.
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
}

/// The outcome of probing a single directory. Distinguishing `failure` from
/// `missing` lets the registry retain partial coverage (for example, a
/// permission-denied root) as evidence instead of silently dropping it.
public enum AIDirectoryProbeResult: Hashable, Sendable {
    case present
    case missing
    case failure(AIToolCoverageFailure)
}

/// Read-only directory presence lookup used to confirm data/skill/plugin roots.
public protocol AIDirectoryProbing: Sendable {
    /// Reports whether a directory exists, is absent, or could not be inspected.
    func probeDirectory(at url: URL) -> AIDirectoryProbeResult
}

public struct LocalAIDirectoryProbe: AIDirectoryProbing {
    public init() {}

    public func probeDirectory(at url: URL) -> AIDirectoryProbeResult {
        // Use throwing resource values rather than `fileExists`, which cannot
        // distinguish "absent" from "parent unreadable (EACCES)" and would
        // misreport a permission failure as `missing`.
        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                // A file where a directory was expected: not the asset we seek.
                return .missing
            }
            // Confirm the directory itself is readable; otherwise its contents
            // cannot be inspected and coverage is partial.
            guard FileManager.default.isReadableFile(atPath: url.path) else {
                return .failure(.permissionDenied)
            }
            return .present
        } catch let error as CocoaError {
            switch error.code {
            case .fileReadNoSuchFile, .fileNoSuchFile:
                return .missing
            case .fileReadNoPermission:
                return .failure(.permissionDenied)
            default:
                return .failure(.unavailable)
            }
        } catch let error as NSError {
            if error.domain == NSPOSIXErrorDomain, error.code == Int(ENOENT) {
                return .missing
            }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(EACCES) {
                return .failure(.permissionDenied)
            }
            return .failure(.unavailable)
        }
    }
}

/// A confirmed directory root paired with its ownership semantics.
private struct ResolvedRoot {
    let url: URL
    let ownership: AIToolRootOwnership
    let displayName: String
}

/// Normalizes discovery results for known AI tools into read-only records.
///
/// Deliberate boundaries:
/// - No UI: does not import SwiftUI.
/// - No scan-scheduling: does not touch `ScanCoordinator`.
/// - No persistence and no writes: never mutates the filesystem or installs,
///   uninstalls, updates, or enables/disables anything.
/// - All environment access (applications, directories, CLI) is injected via
///   protocols, so behavior is fully testable without real processes.
///
/// Records fall into four kinds:
/// - `.application`: the tool as a whole, evidenced by an installed app bundle
///   and/or its data and config roots.
/// - `.cli`: a command-line entry point, evidenced by a whitelisted executable.
/// - `.skill` / `.plugin`: one record per existing Skill or Plugin root. Roots
///   marked shared collapse into a single `owner: .shared` record across every
///   tool that references the same canonical path.
public struct AIToolRegistry: Sendable {
    private let definitions: [AIToolDefinition]
    private let applicationLocator: any AIApplicationLocating
    private let directoryProbe: any AIDirectoryProbing
    private let cliProbe: SafeCLIVersionProbe

    public init(
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all,
        applicationLocator: any AIApplicationLocating,
        directoryProbe: any AIDirectoryProbing = LocalAIDirectoryProbe(),
        cliProbe: SafeCLIVersionProbe = SafeCLIVersionProbe()
    ) {
        self.definitions = definitions
        self.applicationLocator = applicationLocator
        self.directoryProbe = directoryProbe
        self.cliProbe = cliProbe
    }

    /// Discovers all known tools against the given home directory, producing
    /// read-only records for every tool that has any evidence. Tools with no
    /// evidence at all are omitted. IDs are deterministic across runs, so
    /// re-running over an unchanged filesystem yields identical records.
    ///
    /// Cancellation propagates: if the surrounding task is cancelled the method
    /// throws `CancellationError` and does not continue probing later
    /// definitions. Cancellation is never masked as an empty or `unavailable`
    /// result.
    public func discover(homeDirectory: URL) async throws -> [AIToolRecord] {
        var records: [AIToolRecord] = []

        for definition in definitions {
            try Task.checkCancellation()
            let owner = AIToolOwner.tool(definitionID: definition.id)

            let dataRoots = existingDirectories(
                relativePaths: definition.dataRootRelativePaths,
                homeDirectory: homeDirectory
            )
            let configRoots = existingDirectories(
                relativePaths: definition.configRelativePaths,
                homeDirectory: homeDirectory
            )

            if let appRecord = applicationRecord(
                for: definition,
                owner: owner,
                dataRoots: dataRoots.present,
                configRoots: configRoots.present,
                coverageFailures: dataRoots.failures.union(configRoots.failures)
            ) {
                records.append(appRecord)
            }

            if let probeID = definition.cliProbeID {
                if let cliRecord = try await cliRecord(
                    for: definition,
                    owner: owner,
                    probeID: probeID,
                    homeDirectory: homeDirectory
                ) {
                    records.append(cliRecord)
                }
            }

            records.append(contentsOf: rootRecords(
                kind: .skill,
                descriptors: definition.skillRoots,
                definition: definition,
                homeDirectory: homeDirectory
            ))
            records.append(contentsOf: rootRecords(
                kind: .plugin,
                descriptors: definition.pluginRoots,
                definition: definition,
                homeDirectory: homeDirectory
            ))
        }

        return dedupedByID(records)
    }

    // MARK: - Application

    /// Builds the tool-level record. It is emitted when an application bundle is
    /// installed, or when data/config roots exist for the tool. The canonical
    /// location prefers the application URL, then the first data root, then the
    /// first config root, guaranteeing a stable, non-random identifier.
    private func applicationRecord(
        for definition: AIToolDefinition,
        owner: AIToolOwner,
        dataRoots: [URL],
        configRoots: [URL],
        coverageFailures: Set<AIToolCoverageFailure>
    ) -> AIToolRecord? {
        var evidence = AIToolEvidence()
        evidence.dataRoots = dataRoots
        evidence.configDirectories = configRoots

        for bundleID in definition.applicationBundleIdentifiers {
            if let url = applicationLocator.applicationURL(forBundleIdentifier: bundleID) {
                evidence.bundleIdentifier = bundleID
                evidence.applicationURL = url
                break
            }
        }

        let canonical: String
        if let appURL = evidence.applicationURL {
            canonical = Self.canonicalKey(appURL)
        } else if let firstData = dataRoots.first {
            canonical = Self.canonicalKey(firstData)
        } else if let firstConfig = configRoots.first {
            canonical = Self.canonicalKey(firstConfig)
        } else if coverageFailures.isEmpty {
            // No application bundle and no data/config footprint: nothing to show.
            return nil
        } else {
            // Only coverage failures were observed; anchor on the tool ID so the
            // failure is still surfaced rather than dropped.
            canonical = "definition:\(definition.id)"
        }

        return AIToolRecord(
            id: AIToolRecord.stableID(
                kind: .application,
                owner: owner,
                canonicalLocation: canonical
            ),
            kind: .application,
            displayName: definition.displayName,
            owner: owner,
            evidence: evidence,
            coverageFailures: coverageFailures
        )
    }

    // MARK: - CLI

    private func cliRecord(
        for definition: AIToolDefinition,
        owner: AIToolOwner,
        probeID: String,
        homeDirectory: URL
    ) async throws -> AIToolRecord? {
        let result: SafeCLIProbeResult
        do {
            result = try await cliProbe.probeVersion(
                probeID: probeID,
                homeDirectory: homeDirectory
            )
        } catch is CancellationError {
            // Never mask cancellation as a missing/unavailable CLI.
            throw CancellationError()
        } catch is SafeCLIVersionProbe.UnknownProbeError {
            // Definition references a probe not in the whitelist; skip silently.
            return nil
        } catch {
            return nil
        }

        guard let executableURL = result.executableURL else {
            // CLI not installed; no record.
            return nil
        }

        var evidence = AIToolEvidence()
        evidence.executableURL = executableURL
        evidence.detectedVersion = result.version

        var failures = Set<AIToolCoverageFailure>()
        if let failure = result.coverageFailure {
            failures.insert(failure)
        }

        return AIToolRecord(
            id: AIToolRecord.stableID(
                kind: .cli,
                owner: owner,
                canonicalLocation: Self.canonicalKey(executableURL)
            ),
            kind: .cli,
            displayName: definition.displayName,
            owner: owner,
            evidence: evidence,
            coverageFailures: failures
        )
    }

    // MARK: - Skills & Plugins

    private func rootRecords(
        kind: AIToolKind,
        descriptors: [AIToolRootDescriptor],
        definition: AIToolDefinition,
        homeDirectory: URL
    ) -> [AIToolRecord] {
        var records: [AIToolRecord] = []
        for descriptor in descriptors {
            let url = homeDirectory.appending(
                path: descriptor.relativePath,
                directoryHint: .isDirectory
            )
            let canonical = Self.canonicalKey(url)
            let owner: AIToolOwner = descriptor.ownership == .shared
                ? .shared
                : .tool(definitionID: definition.id)
            let displayName = descriptor.displayNameOverride ?? definition.displayName

            var evidence = AIToolEvidence()
            switch kind {
            case .skill:
                evidence.skillRoots = [url]
            case .plugin:
                evidence.pluginRoots = [url]
            case .application, .cli:
                break
            }

            switch directoryProbe.probeDirectory(at: url) {
            case .present:
                records.append(AIToolRecord(
                    id: AIToolRecord.stableID(
                        kind: kind,
                        owner: owner,
                        canonicalLocation: canonical
                    ),
                    kind: kind,
                    displayName: displayName,
                    owner: owner,
                    evidence: evidence
                ))
            case .failure(let failure):
                // Retain partial coverage rather than silently dropping the root.
                records.append(AIToolRecord(
                    id: AIToolRecord.stableID(
                        kind: kind,
                        owner: owner,
                        canonicalLocation: canonical
                    ),
                    kind: kind,
                    displayName: displayName,
                    owner: owner,
                    evidence: evidence,
                    coverageFailures: [failure]
                ))
            case .missing:
                continue
            }
        }
        return records
    }

    // MARK: - Directories

    private struct DirectoryScanOutcome {
        var present: [URL] = []
        var failures: Set<AIToolCoverageFailure> = []
    }

    private func existingDirectories(
        relativePaths: [String],
        homeDirectory: URL
    ) -> DirectoryScanOutcome {
        var seen = Set<String>()
        var outcome = DirectoryScanOutcome()
        for relative in relativePaths {
            let url = homeDirectory.appending(path: relative, directoryHint: .isDirectory)
            let canonical = Self.canonicalKey(url)
            guard seen.insert(canonical).inserted else { continue }
            switch directoryProbe.probeDirectory(at: url) {
            case .present:
                outcome.present.append(url)
            case .failure(let failure):
                outcome.failures.insert(failure)
            case .missing:
                continue
            }
        }
        return outcome
    }

    /// Produces a canonical key for a URL, resolving symbolic links and
    /// standardizing the path so that symlinked or `..`-laden paths that point
    /// at the same location deduplicate correctly.
    static func canonicalKey(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: - Dedup

    /// Collapses records that share a deterministic ID, merging their evidence
    /// and coverage failures so overlapping definitions never double-count the
    /// same canonical location. Because shared roots use `owner: .shared`, the
    /// same shared directory referenced by multiple tools collapses into one
    /// record here.
    private func dedupedByID(_ records: [AIToolRecord]) -> [AIToolRecord] {
        var order: [String] = []
        var merged: [String: AIToolRecord] = [:]
        for record in records {
            if var existing = merged[record.id] {
                existing.evidence.merge(record.evidence)
                existing.coverageFailures.formUnion(record.coverageFailures)
                merged[record.id] = existing
            } else {
                merged[record.id] = record
                order.append(record.id)
            }
        }
        return order.compactMap { merged[$0] }
    }
}
