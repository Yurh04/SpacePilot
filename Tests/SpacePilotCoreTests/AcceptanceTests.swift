import XCTest
@testable import SpacePilotCore

final class AcceptanceTests: XCTestCase {
    func testAcceptanceFixtureMeetsSafetyAndRelationshipRequirements() async throws {
        let fixture = try AcceptanceFixture.make()

        let snapshot = try await fixture.coordinator.collectScan()

        XCTAssertTrue(snapshot.applications.contains { $0.bundleIdentifier == "com.example.One" })
        XCTAssertTrue(snapshot.applications.contains { $0.bundleIdentifier == "com.example.Two" })
        let associatedIDs = Set(snapshot.applications.flatMap(\.associations).map(\.itemID))
        XCTAssertFalse(snapshot.items.contains { $0.url == fixture.userDocument && associatedIDs.contains($0.id) })
        XCTAssertFalse(OverviewProjection(snapshot: snapshot).preselectedRecommendations.contains { $0.url == fixture.userDocument })

        let codex = try XCTUnwrap(snapshot.aiApplications.first { $0.name == "Codex" })
        let claude = try XCTUnwrap(snapshot.aiApplications.first { $0.name == "Claude" })
        let chatGPT = try XCTUnwrap(snapshot.aiApplications.first { $0.name == "ChatGPT" })
        XCTAssertFalse(codex.itemIDs.isEmpty)
        XCTAssertFalse(claude.itemIDs.isEmpty)
        XCTAssertFalse(snapshot.plugins.isEmpty)
        XCTAssertEqual(codex.pluginIDs, Set(snapshot.plugins.map(\.id)))
        XCTAssertTrue(snapshot.aiApplications.filter { $0.name != "Codex" }.allSatisfy(\.pluginIDs.isEmpty))
        XCTAssertNotNil(snapshot.pluginDiagnostics)
        XCTAssertEqual(chatGPT.supportLevel, .basic)
        XCTAssertTrue(snapshot.items.contains { $0.category == .developer && $0.url.path.contains("_cacache") })
        XCTAssertTrue(snapshot.skills.contains { $0.scope == .sharedAgents })
        XCTAssertTrue(snapshot.skills.contains { $0.scope == .agentSpecific(agent: "Codex") })
        XCTAssertTrue(snapshot.skills.contains { $0.scope == .agentSpecific(agent: "Claude") })
        XCTAssertTrue(snapshot.skills.contains { $0.managementStatus == .parentManaged })
        XCTAssertTrue(snapshot.skills.contains { $0.managementStatus == .systemReadOnly })
        XCTAssertTrue(snapshot.skills.contains { $0.conflict == .agentOverride })

        let uniqueItemIDs = Set(snapshot.aiApplications.flatMap(\.itemIDs))
        let uniqueSkillIDs = Set(snapshot.aiApplications.flatMap(\.skillIDs))
        let independentlyCalculated = snapshot.aiApplications.reduce(0) { $0 + $1.applicationAllocatedSize }
            + snapshot.items.filter { uniqueItemIDs.contains($0.id) }.reduce(0) { $0 + $1.allocatedSize }
            + snapshot.skills.filter { uniqueSkillIDs.contains($0.id) }.reduce(0) { $0 + $1.allocatedSize }
        XCTAssertEqual(snapshot.uniqueAIAllocatedSize, independentlyCalculated)
    }
}
