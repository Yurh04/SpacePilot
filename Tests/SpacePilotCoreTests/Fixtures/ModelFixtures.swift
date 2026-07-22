import Foundation
@testable import SpacePilotCore

extension ScannedItem {
    static func fixture(
        id: UUID = UUID(),
        path: String = "/Users/test/Library/Caches/app/file",
        risk: RiskLevel = .safe,
        allocatedSize: Int64 = 0,
        modificationDate: Date? = nil,
        resourceIdentifier: String? = nil
    ) -> Self {
        .init(
            id: id,
            url: URL(fileURLWithPath: path),
            logicalSize: allocatedSize,
            allocatedSize: allocatedSize,
            modificationDate: modificationDate,
            resourceIdentifier: resourceIdentifier,
            category: .cache,
            risk: risk,
            explanation: "Fixture"
        )
    }
}

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
        scope: SkillScope = .sharedAgents,
        parentPluginID: UUID? = nil
    ) -> Self {
        .init(
            id: id,
            name: "fixture-skill",
            summary: "Fixture skill",
            url: URL(fileURLWithPath: "/Users/test/.agents/skills/fixture-skill"),
            allocatedSize: allocatedSize,
            scope: scope,
            visibleAgents: ["Codex", "Claude"],
            parentPluginID: parentPluginID,
            fingerprint: "fixture",
            conflict: nil,
            managementStatus: parentPluginID == nil ? .standalone : .parentManaged
        )
    }
}

extension ScanSnapshot {
    static func fixture(
        id: UUID = UUID(),
        completedAt: Date = .now,
        aiApplications: [AIApplicationRecord] = [],
        skills: [SkillRecord] = [],
        pluginDiagnostics: [String]? = nil
    ) -> Self {
        .init(
            id: id,
            completedAt: completedAt,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: aiApplications,
            plugins: [],
            skills: skills,
            coverage: .complete,
            pluginDiagnostics: pluginDiagnostics
        )
    }
}
