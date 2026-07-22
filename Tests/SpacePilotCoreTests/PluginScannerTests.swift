import XCTest
@testable import SpacePilotCore

final class PluginScannerTests: XCTestCase {
    func testDirectorySkillsDeclarationDiscoversChildSkills() async throws {
        let fixture = try PluginFixture.make(
            name: "product-design",
            version: "0.1.52",
            skillNames: ["index", "audit"],
            skillsEncoding: .directory("./skills/")
        )

        let result = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [fixture.root])

        let plugin = try XCTUnwrap(result.plugins.first)
        XCTAssertEqual(plugin.name, "product-design")
        XCTAssertEqual(plugin.skillIDs.count, 2)
        XCTAssertEqual(Set(result.skills.map(\.name)), ["index", "audit"])
        XCTAssertTrue(result.skills.allSatisfy { $0.parentPluginID == plugin.id })
    }

    func testPluginOwnsBundledSkills() async throws {
        let plugin = try PluginFixture.make(
            name: "product-design",
            version: "0.1.52",
            skillNames: ["index", "audit"]
        )

        let result = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [plugin.root])

        XCTAssertEqual(result.plugins.first?.version, "0.1.52")
        XCTAssertEqual(result.plugins.first?.managementCapability, .officialHandoff)
        XCTAssertEqual(result.skills.count, 2)
        XCTAssertTrue(result.skills.allSatisfy { $0.managementStatus == .parentManaged })
        XCTAssertTrue(result.skills.allSatisfy { $0.parentPluginID == result.plugins.first?.id })
        XCTAssertEqual(result.plugins.first?.skillIDs.count, 2)
    }

    func testTraversalSkillPathIsRejectedWithDiagnostic() async throws {
        let plugin = try PluginFixture.make(
            name: "unsafe-plugin",
            version: "1.0.0",
            skillNames: ["safe"],
            extraSkillPaths: ["../../outside"]
        )

        let result = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [plugin.root])

        XCTAssertEqual(result.skills.map(\.name), ["safe"])
        XCTAssertTrue(result.diagnostics.contains { $0.contains("../../outside") })
    }

    func testBundledSkillCannotEnterCleanupPlan() async throws {
        let plugin = try PluginFixture.make(name: "managed", version: "1", skillNames: ["child"])
        let result = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [plugin.root])
        let skill = try XCTUnwrap(result.skills.first)
        let item = ScannedItem(
            url: skill.url,
            logicalSize: 1,
            allocatedSize: skill.allocatedSize,
            category: .skill,
            risk: .managed,
            explanation: "Managed by Plugin"
        )
        let planner = CleanupPlanner(policy: PathSafetyPolicy(
            homeDirectory: plugin.tree.url,
            allowedVolumeRoot: plugin.tree.url
        ))

        XCTAssertThrowsError(try planner.makePlan(
            snapshotID: UUID(),
            items: [item],
            selectedIDs: [item.id],
            separatelyConfirmedSensitiveIDs: []
        )) { error in
            XCTAssertEqual(error as? CleanupPlanningError, .managedItem(item.url))
        }
    }
}
