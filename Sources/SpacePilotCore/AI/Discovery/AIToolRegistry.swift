import Foundation

/// Read-only application presence lookup, injected so discovery is deterministic
/// in tests and never touches `NSWorkspace` directly from core.
public protocol AIApplicationLocating: Sendable {
    /// Returns the on-disk URL of an installed application for a bundle
    /// identifier, or `nil` if it is not installed.
    func applicationURL(forBundleIdentifier bundleIdentifier: String) -> URL?
    func applicationVersion(forBundleIdentifier bundleIdentifier: String) -> String?
}

public extension AIApplicationLocating {
    func applicationVersion(forBundleIdentifier bundleIdentifier: String) -> String? { nil }
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
        // CLI probing is the one slow, blocking part of discovery: each probe may
        // spawn a subprocess and wait up to the per-probe timeout. Run every
        // probe concurrently up front, then assemble records in the original
        // serial order below so the output — and thus `dedupedByID`'s
        // first-appearance ordering — is byte-for-byte identical to a fully
        // serial pass.
        let probeResults = try await probeAllCLIs(homeDirectory: homeDirectory)

        var records: [AIToolRecord] = []

        for definition in definitions {
            try Task.checkCancellation()
            let owner = AIToolOwner.tool(definitionID: definition.id)

            let installedBundleIDs = definition.applicationBundleIdentifiers.filter {
                applicationLocator.applicationURL(forBundleIdentifier: $0) != nil
            }
            let bundleRoots = installedBundleIDs.flatMap { id in
                ["Library/Application Support/\(id)", "Library/Caches/\(id)",
                 "Library/Logs/\(id)", "Library/Containers/\(id)"]
            }
            let dataRoots = existingDirectories(
                relativePaths: definition.dataRootRelativePaths + bundleRoots,
                homeDirectory: homeDirectory
            )
            let configRoots = existingDirectories(
                relativePaths: definition.configRelativePaths,
                homeDirectory: homeDirectory
            )
            let hostEvidenceRoots = existingDirectories(
                relativePaths: definition.hostEvidenceRelativePaths,
                homeDirectory: homeDirectory
            )

            if let appRecord = applicationRecord(
                for: definition,
                owner: owner,
                dataRoots: dataRoots.present,
                configRoots: configRoots.present,
                hostEvidenceRoots: hostEvidenceRoots.present,
                coverageFailures: dataRoots.failures.union(configRoots.failures)
                    .union(hostEvidenceRoots.failures)
            ) {
                records.append(appRecord)
            }

            if definition.cliProbeID != nil,
               let result = probeResults[definition.id],
               let cliRecord = cliRecord(
                   from: result, for: definition, owner: owner,
                   dataRoots: dataRoots.present, configRoots: configRoots.present,
                   coverageFailures: dataRoots.failures.union(configRoots.failures)
               ) {
                records.append(cliRecord)
            }

            // Directory-backed presence: for opted-in definitions with no app and
            // no runnable CLI, the existence of the managed directory is itself
            // the evidence the tool is installed (installed from source, or a
            // command outside the fixed probe locations). Emitted as a `.cli`
            // record with no executable so existing consumers treat it uniformly;
            // gated so a leftover dot-directory never fabricates a tool.
            if let presenceRecord = directoryPresenceRecord(
                for: definition,
                owner: owner,
                dataRoots: dataRoots.present,
                configRoots: configRoots.present,
                alreadyHasAppOrCLI: records.contains { $0.owner == owner
                    && ($0.kind == .application || $0.kind == .cli) }
            ) {
                records.append(presenceRecord)
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

    /// Runs every definition's CLI version probe concurrently, keyed by the
    /// owning definition's id. A bounded window caps how many child processes can
    /// be in flight at once so a machine with many installed CLIs never spawns
    /// them all simultaneously; probes for tools that are not installed return
    /// almost immediately without spawning anything.
    ///
    /// Cancellation propagates: a cancelled child throws `CancellationError`,
    /// which `group.next()` rethrows here and which cancels the remaining
    /// children. Unknown-probe and probe errors are absorbed as "no result" (the
    /// definition simply produces no CLI record), matching the serial behavior.
    private func probeAllCLIs(homeDirectory: URL) async throws -> [String: SafeCLIProbeResult] {
        let probeTargets: [(definitionID: String, probeID: String)] = definitions.compactMap {
            guard let probeID = $0.cliProbeID else { return nil }
            return ($0.id, probeID)
        }
        guard !probeTargets.isEmpty else { return [:] }

        // Generous enough to probe every realistically-installed CLI at once,
        // while still bounding the worst case where many probes must time out.
        let maxConcurrent = 8

        var results: [String: SafeCLIProbeResult] = [:]
        results.reserveCapacity(probeTargets.count)

        try await withThrowingTaskGroup(
            of: (String, SafeCLIProbeResult?).self
        ) { group in
            var next = 0
            let window = min(maxConcurrent, probeTargets.count)
            while next < window {
                let target = probeTargets[next]
                group.addTask {
                    (target.definitionID, try await self.probeResult(probeID: target.probeID, homeDirectory: homeDirectory))
                }
                next += 1
            }

            while let (definitionID, result) = try await group.next() {
                if let result { results[definitionID] = result }
                if next < probeTargets.count {
                    let target = probeTargets[next]
                    group.addTask {
                        (target.definitionID, try await self.probeResult(probeID: target.probeID, homeDirectory: homeDirectory))
                    }
                    next += 1
                }
            }
        }

        return results
    }

    /// Probes one CLI, mapping the probe's expected errors to `nil` (no record)
    /// while re-throwing cancellation so it is never masked as a missing CLI.
    private func probeResult(
        probeID: String,
        homeDirectory: URL
    ) async throws -> SafeCLIProbeResult? {
        do {
            return try await cliProbe.probeVersion(probeID: probeID, homeDirectory: homeDirectory)
        } catch is CancellationError {
            throw CancellationError()
        } catch is SafeCLIVersionProbe.UnknownProbeError {
            // Definition references a probe not in the whitelist; skip silently.
            return nil
        } catch {
            return nil
        }
    }

    // MARK: - Application

    /// Builds the application-level record. It is emitted *only* when a real
    /// application bundle from `applicationBundleIdentifiers` is installed and
    /// located by the injected locator. Data/config roots and host-evidence
    /// roots attach as supplemental evidence but never fabricate an app on
    /// their own, so a leftover config directory (`~/.cursor`,
    /// `~/.config/opencode`) or a CLI-only tool's dot-directory can never
    /// appear as an installed AI application. The canonical location is the
    /// application URL, guaranteeing a stable, non-random identifier.
    private func applicationRecord(
        for definition: AIToolDefinition,
        owner: AIToolOwner,
        dataRoots: [URL],
        configRoots: [URL],
        hostEvidenceRoots: [URL],
        coverageFailures: Set<AIToolCoverageFailure>
    ) -> AIToolRecord? {
        // An AI App record must correspond to a *real installed application
        // bundle*. Config/data footprints (for example a leftover `~/.cursor`
        // or `~/.config/opencode` after uninstalling the app, or a CLI-only
        // tool's dot-directory) must never fabricate an application. Those
        // footprints only attach as supplemental evidence to an app that is
        // actually installed.
        guard !definition.applicationBundleIdentifiers.isEmpty else {
            // CLI-only definition (OpenCode, Gemini CLI, Aider, ...). It can
            // still produce a `.cli` record elsewhere, but never an app.
            return nil
        }

        var evidence = AIToolEvidence()
        for bundleID in definition.applicationBundleIdentifiers {
            if let url = applicationLocator.applicationURL(forBundleIdentifier: bundleID) {
                evidence.bundleIdentifier = bundleID
                evidence.applicationURL = url
                evidence.detectedVersion = applicationLocator.applicationVersion(forBundleIdentifier: bundleID)
                break
            }
        }

        // No installed bundle: this application is not present, regardless of
        // any config/data footprint. Do not emit an application record.
        guard let appURL = evidence.applicationURL else {
            return nil
        }

        if !definition.hostEvidenceRelativePaths.isEmpty,
           hostEvidenceRoots.isEmpty,
           coverageFailures.isEmpty {
            // A generic AI-enabled host (VS Code, etc.) requires fixed AI
            // extension/config evidence. A bundle alone, or a broad extensions
            // directory, is not enough to enter AI management.
            return nil
        }

        // The app is installed; attach the data/config footprint as evidence.
        evidence.dataRoots = dataRoots
        evidence.configDirectories = AIToolEvidence.mergeURLsForDiscovery(
            configRoots,
            hostEvidenceRoots
        )

        return AIToolRecord(
            id: AIToolRecord.stableID(
                kind: .application,
                owner: owner,
                canonicalLocation: Self.canonicalKey(appURL)
            ),
            kind: .application,
            displayName: definition.displayName,
            owner: owner,
            evidence: evidence,
            coverageFailures: coverageFailures
        )
    }

    // MARK: - CLI

    /// Builds a CLI record from an already-computed probe result. Pure and
    /// synchronous: the process work happened in `probeAllCLIs`, so record
    /// assembly can run in the original serial order without any awaiting.
    private func cliRecord(
        from result: SafeCLIProbeResult,
        for definition: AIToolDefinition,
        owner: AIToolOwner,
        dataRoots: [URL],
        configRoots: [URL],
        coverageFailures: Set<AIToolCoverageFailure>
    ) -> AIToolRecord? {
        guard let executableURL = result.executableURL else {
            // CLI not installed; no record.
            return nil
        }

        var evidence = AIToolEvidence()
        evidence.executableURL = executableURL
        evidence.detectedVersion = result.version
        evidence.aliasExecutableURLs = result.aliasExecutableURLs
        evidence.dataRoots = dataRoots
        evidence.configDirectories = configRoots

        var failures = coverageFailures
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

    /// Builds a directory-backed presence record for a definition that opted into
    /// `surfacesFromDirectoryPresence` and produced no application or CLI record.
    ///
    /// The tool is proven present by its managed directory alone (data root
    /// preferred, else config root). The record is a `.cli` with no executable —
    /// so version/update/reveal code paths degrade gracefully — anchored to the
    /// directory so its identifier stays stable across scans. Returns `nil` when
    /// the definition did not opt in, when an app/CLI record already represents
    /// it, or when no managed directory exists (so nothing is fabricated).
    private func directoryPresenceRecord(
        for definition: AIToolDefinition,
        owner: AIToolOwner,
        dataRoots: [URL],
        configRoots: [URL],
        alreadyHasAppOrCLI: Bool
    ) -> AIToolRecord? {
        guard definition.surfacesFromDirectoryPresence, !alreadyHasAppOrCLI else {
            return nil
        }
        guard let anchor = dataRoots.first ?? configRoots.first else {
            return nil
        }

        var evidence = AIToolEvidence()
        evidence.dataRoots = dataRoots
        evidence.configDirectories = configRoots

        return AIToolRecord(
            id: AIToolRecord.stableID(
                kind: .cli,
                owner: owner,
                canonicalLocation: Self.canonicalKey(anchor)
            ),
            kind: .cli,
            displayName: definition.displayName,
            owner: owner,
            evidence: evidence
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
    /// at the same location deduplicate correctly. Delegates to the shared
    /// `canonicalizedDiscoveryPath` so every discovery keying site agrees on one
    /// normalization order.
    static func canonicalKey(_ url: URL) -> String {
        url.canonicalizedDiscoveryPath
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
