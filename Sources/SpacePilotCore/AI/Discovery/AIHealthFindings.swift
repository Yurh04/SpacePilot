import Foundation

/// A single read-only "health finding" for the Developer & AI overview: a
/// noteworthy condition discovery already proved, phrased as a
/// non-localized token set so the view owns wording and localisation.
///
/// This is a pure aggregation over inputs already in memory — duplication
/// analysis, discovered records, and hook evidence. It performs no file-system
/// access and invents nothing: every finding is backed by concrete data, and an
/// empty machine yields an empty list.
public struct AIHealthFinding: Identifiable, Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// Skill content stored in more than one physical location.
        case duplicateStorage
        /// A single AI-owned directory whose footprint is unusually large.
        case largeFootprint
        /// An Agent's hook event whose handlers all come from one external app.
        case hookTakeover
        /// Skills exposed only through symlinks (fragile: break if the target's
        /// owner is removed), or symlinks whose target is already gone.
        case symlinkDependency
        /// A real skill copy that nothing references, while the same content is
        /// reached elsewhere via a symlink — the copy is dead weight.
        case unreferencedSkill
    }

    public enum Severity: Int, Hashable, Sendable, Comparable {
        case info
        case warning

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let id: String
    public let kind: Kind
    public let severity: Severity
    /// The primary subject (a skill name, directory basename, or provider name).
    public let subject: String
    /// A secondary factual detail (a path, an Agent name, an event name). May be
    /// empty when the subject alone is sufficient.
    public let detail: String
    /// Bytes relevant to the finding (reclaimable duplication, or footprint size).
    /// Zero when the finding has no size dimension.
    public let byteCount: Int64

    public init(
        id: String,
        kind: Kind,
        severity: Severity,
        subject: String,
        detail: String,
        byteCount: Int64
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.subject = subject
        self.detail = detail
        self.byteCount = byteCount
    }
}

public enum AIHealthFindings {
    /// A directory must exceed this allocated size to be flagged as a large
    /// footprint. A code constant, sized so everyday AI state does not trip it but
    /// a genuinely large data/checkpoint store does.
    public static let largeFootprintThreshold: Int64 = 1_000 * 1_024 * 1_024 // 1 GB

    /// At most this many large-footprint findings, largest first, so one machine
    /// with many big directories does not flood the list.
    public static let maxLargeFootprints = 3

    /// Builds the overview's health findings from data already discovered.
    ///
    /// - `duplication`: result of `SkillDuplicationAnalyzer.analyze`.
    /// - `records`: all discovered `AIToolRecord`s (used for large footprints,
    ///   measured from each record's data roots via `sizesByPath`).
    /// - `sizesByPath`: allocated size keyed by canonical path (the same table the
    ///   detail pane already computes), used to size large-footprint findings
    ///   without re-touching the disk.
    /// - `hooks`: discovered hook records, used for takeover detection.
    public static func analyze(
        duplication: SkillDuplicationAnalyzer.Result,
        sizesByPath: [String: Int64],
        hooks: [HookRecord],
        skills: [SkillRecord] = []
    ) -> [AIHealthFinding] {
        var findings: [AIHealthFinding] = []

        // 1. Duplicate storage — one finding summarising the reclaimable total,
        // only when at least one entity is genuinely duplicated.
        if duplication.duplicatedEntityCount > 0 {
            findings.append(AIHealthFinding(
                id: "dup",
                kind: .duplicateStorage,
                severity: .warning,
                subject: String(duplication.duplicatedEntityCount),
                detail: "",
                byteCount: duplication.totalReclaimable
            ))
        }

        // 2. Large footprints — directories over the threshold, largest first,
        // capped. Keyed by canonical path so the same directory is counted once.
        let largest = sizesByPath
            .filter { $0.value >= largeFootprintThreshold }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key < rhs.key
            }
            .prefix(maxLargeFootprints)
        for (path, size) in largest {
            findings.append(AIHealthFinding(
                id: "big:\(path)",
                kind: .largeFootprint,
                severity: .warning,
                subject: (path as NSString).lastPathComponent,
                detail: path,
                byteCount: size
            ))
        }

        // 3. Hook takeover — an event whose handlers are all attributed to a
        // single external provider. `providers` is only populated from an
        // unambiguous /Applications/<App>.app path, so a non-empty single-provider
        // set is strong evidence the event is driven by that external app.
        for hook in hooks.sorted(by: { ($0.ownerDefinitionID, $0.event) < ($1.ownerDefinitionID, $1.event) }) {
            let distinct = Set(hook.providers)
            guard distinct.count == 1, let provider = distinct.first, hook.handlerCount > 0 else { continue }
            findings.append(AIHealthFinding(
                id: "hook:\(hook.ownerDefinitionID):\(hook.event)",
                kind: .hookTakeover,
                severity: .info,
                subject: provider,
                detail: "\(hook.ownerDefinitionID) · \(hook.event)",
                byteCount: 0
            ))
        }

        // 4. Symlink dependency — skills that exist only as symlinks. A broken
        // link (target gone) is a warning; a live symlinked skill is info-level
        // ("depends on an external target"). Summarised as one finding each, so a
        // machine with many linked skills does not flood the list.
        let symlinked = skills.filter { $0.symlinkTarget != nil }
        let broken = symlinked.filter(\.isSymlinkBroken)
        if !broken.isEmpty {
            findings.append(AIHealthFinding(
                id: "symlink-broken",
                kind: .symlinkDependency,
                severity: .warning,
                subject: String(broken.count),
                detail: "",
                byteCount: 0
            ))
        }
        let liveLinked = symlinked.count - broken.count
        if liveLinked > 0 {
            findings.append(AIHealthFinding(
                id: "symlink-live",
                kind: .symlinkDependency,
                severity: .info,
                subject: String(liveLinked),
                detail: "",
                byteCount: 0
            ))
        }

        // 5. Unreferenced skills — real (non-symlink) skill copies that no symlink
        // points at, whose identical content is *also* present at a location that
        // IS referenced by a symlink. Such a copy is dead weight: nothing loads it,
        // and deleting it would not lose content (the referenced copy remains).
        // Deliberately conservative: a real skill with no duplicate elsewhere is
        // never flagged, because it may well be the one true copy in use.
        let referencedPaths = Set(
            skills.compactMap { $0.symlinkTarget?.canonicalizedDiscoveryPath }
        )
        var fingerprintReferenced: [String: Bool] = [:]
        for skill in skills where !skill.fingerprint.isEmpty {
            let isReferenced = referencedPaths.contains(skill.url.canonicalizedDiscoveryPath)
            fingerprintReferenced[skill.fingerprint] = (fingerprintReferenced[skill.fingerprint] ?? false) || isReferenced
        }
        let unreferenced = skills.filter { skill in
            guard skill.symlinkTarget == nil, !skill.fingerprint.isEmpty else { return false }
            let path = skill.url.canonicalizedDiscoveryPath
            guard !referencedPaths.contains(path) else { return false }
            // The same content must be reachable via a referenced copy elsewhere.
            return fingerprintReferenced[skill.fingerprint] == true
        }
        if !unreferenced.isEmpty {
            let reclaimable = unreferenced.reduce(Int64(0)) { $0 + $1.allocatedSize }
            findings.append(AIHealthFinding(
                id: "unreferenced-skills",
                kind: .unreferencedSkill,
                severity: .warning,
                subject: String(unreferenced.count),
                detail: "",
                byteCount: reclaimable
            ))
        }

        return findings
    }
}
