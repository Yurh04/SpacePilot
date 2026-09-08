import Foundation

/// Finds Skills whose *content* is stored more than once on disk, and computes
/// how much space the duplication actually costs.
///
/// Two rules make this honest, and both were derived from what is really on this
/// machine rather than assumed:
///
/// 1. **Group by content, not by name.** Of 40 same-named Skill pairs found in
///    two stores here, 39 were byte-identical and one (`archify`) had genuinely
///    diverged. Grouping by name alone would have reported that one as
///    reclaimable when deleting either copy would lose real content.
/// 2. **Count an entity once; symlinks are not copies.** Both `~/.codex/skills`
///    and `~/.claude/skills` are 54 symlinks into a single real store. Counting
///    those as 108 extra copies would inflate the total by an order of
///    magnitude. Only distinct physical locations count.
public enum SkillDuplicationAnalyzer {
    /// One group of Skills that share identical content across several locations.
    public struct DuplicateGroup: Identifiable, Hashable, Sendable {
        /// The shared content fingerprint; stable across runs.
        public let id: String
        public let name: String
        /// Every distinct physical location holding this content, ordered.
        public let locations: [URL]
        /// Size of a single copy.
        public let unitSize: Int64

        /// How many physical copies exist.
        public var copyCount: Int { locations.count }

        /// Space that would be freed by keeping exactly one copy. This is the
        /// only number safe to present as "reclaimable".
        public var reclaimableSize: Int64 { unitSize * Int64(max(0, copyCount - 1)) }
    }

    public struct Result: Sendable, Equatable {
        public let groups: [DuplicateGroup]
        /// Total space attributable to redundant copies.
        public let totalReclaimable: Int64
        /// Number of Skill entities (not copies) that are stored more than once.
        public var duplicatedEntityCount: Int { groups.count }
    }

    /// Groups `skills` by content fingerprint and reports those stored in more
    /// than one physical location.
    ///
    /// Records whose canonical path collapses onto one already seen are dropped
    /// before grouping, so a symlinked view of a store never counts as an extra
    /// copy.
    public static func analyze(skills: [SkillRecord]) -> Result {
        var seenCanonical = Set<String>()
        var byFingerprint: [String: [SkillRecord]] = [:]
        var order: [String] = []

        for skill in skills {
            // Resolve symlinks so that N linked views of one directory collapse
            // to the single physical location they share.
            let canonical = skill.url.canonicalizedDiscoveryPath
            guard seenCanonical.insert(canonical).inserted else { continue }

            // An empty fingerprint means content could not be hashed; such a
            // record cannot be proven to duplicate anything, so it is excluded
            // rather than guessed at.
            guard !skill.fingerprint.isEmpty else { continue }

            if byFingerprint[skill.fingerprint] == nil { order.append(skill.fingerprint) }
            byFingerprint[skill.fingerprint, default: []].append(skill)
        }

        var groups: [DuplicateGroup] = []
        for fingerprint in order {
            guard let members = byFingerprint[fingerprint], members.count > 1 else { continue }
            let sorted = members.sorted { $0.url.path < $1.url.path }
            groups.append(DuplicateGroup(
                id: fingerprint,
                name: sorted[0].name,
                locations: sorted.map(\.url),
                // Copies are identical by construction, so any member's size is
                // the unit size; take the max to stay safe if sizes were sampled
                // at slightly different times.
                unitSize: sorted.map(\.allocatedSize).max() ?? 0
            ))
        }

        groups.sort { lhs, rhs in
            if lhs.reclaimableSize != rhs.reclaimableSize {
                return lhs.reclaimableSize > rhs.reclaimableSize
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        return Result(
            groups: groups,
            totalReclaimable: groups.reduce(0) { $0 + $1.reclaimableSize }
        )
    }
}
