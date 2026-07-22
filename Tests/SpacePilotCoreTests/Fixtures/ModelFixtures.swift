import Foundation
@testable import SpacePilotCore

extension AIApplicationRecord {
    static func fixture(
        id: UUID = UUID(),
        name: String = "AI App",
        itemIDs: Set<UUID> = [],
        pluginIDs: Set<UUID> = [],
        skillIDs: Set<UUID> = [],
        applicationAllocatedSize: Int64 = 0
    ) -> Self {
        .init(
            id: id,
            name: name,
            bundleIdentifier: nil,
            applicationURL: nil,
            rootURLs: [],
            itemIDs: itemIDs,
            pluginIDs: pluginIDs,
            skillIDs: skillIDs,
            applicationAllocatedSize: applicationAllocatedSize,
            supportLevel: .deep
        )
    }
}

extension SkillRecord {
    static func fixture(
        id: UUID = UUID(),
        allocatedSize: Int64 = 0,
        scope: SkillScope = .sharedAgents
    ) -> Self {
        .init(
            id: id,
            name: "fixture-skill",
            summary: "Fixture skill",
            url: URL(fileURLWithPath: "/Users/test/.agents/skills/fixture-skill"),
            allocatedSize: allocatedSize,
            scope: scope,
            visibleAgents: ["Codex", "Claude"],
            parentPluginID: nil,
            fingerprint: "fixture",
            conflict: nil,
            managementStatus: .standalone
        )
    }
}

extension ScanSnapshot {
    static func fixture(
        id: UUID = UUID(),
        aiApplications: [AIApplicationRecord] = [],
        skills: [SkillRecord] = []
    ) -> Self {
        .init(
            id: id,
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: aiApplications,
            plugins: [],
            skills: skills,
            coverage: .complete
        )
    }
}
