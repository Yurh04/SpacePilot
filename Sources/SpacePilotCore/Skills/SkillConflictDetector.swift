import Foundation

public struct SkillConflictDetector: Sendable {
    public init() {}

    public func detect(in records: [SkillRecord]) -> [SkillRecord] {
        let groups = Dictionary(grouping: records) { $0.name.lowercased() }
        return records.map { record in
            let peers = groups[record.name.lowercased(), default: []]
            let conflict = conflict(for: record, peers: peers)
            return SkillRecord(
                id: record.id,
                name: record.name,
                summary: record.summary,
                url: record.url,
                allocatedSize: record.allocatedSize,
                scope: record.scope,
                visibleAgents: record.visibleAgents,
                parentPluginID: record.parentPluginID,
                fingerprint: record.fingerprint,
                conflict: conflict,
                managementStatus: record.managementStatus
            )
        }
    }

    private func conflict(for record: SkillRecord, peers: [SkillRecord]) -> SkillConflict? {
        guard peers.count > 1 else { return nil }
        if peers.allSatisfy({ $0.fingerprint == record.fingerprint }) {
            return .exactDuplicate
        }
        if case .agentSpecific = record.scope,
           peers.contains(where: { $0.scope == .sharedAgents }) {
            return .agentOverride
        }
        return .sameNameDifferentContent
    }
}
