import Foundation
import XCTest
@testable import SpacePilotCore

final class AIApplicationProductFamilyMergerTests: XCTestCase {
    func testMergesChatGPTAndCodexWithoutDoubleCountingApplicationBundle() {
        let codexItemID = UUID()
        let chatGPTItemID = UUID()
        let pluginID = UUID()
        let skillID = UUID()
        let codexID = UUID()
        let codex = application(
            id: codexID,
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            applicationURL: nil,
            roots: ["/Users/test/.codex"],
            itemIDs: [codexItemID],
            pluginIDs: [pluginID],
            skillIDs: [skillID],
            applicationSize: 1_000,
            supportLevel: .deep
        )
        let chatGPTURL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
        let chatGPT = application(
            name: "ChatGPT",
            bundleIdentifier: "com.openai.chat",
            applicationURL: chatGPTURL,
            roots: [
                "/Users/test/.codex",
                "/Users/test/Library/Application Support/ChatGPT"
            ],
            itemIDs: [chatGPTItemID],
            applicationSize: 1_400,
            supportLevel: .basic
        )
        let claude = application(
            name: "Claude",
            bundleIdentifier: "com.anthropic.claudefordesktop",
            roots: ["/Users/test/.claude"],
            supportLevel: .deep
        )

        let result = AIApplicationProductFamilyMerger()
            .mergeChatGPTAndCodex(in: [codex, claude, chatGPT])

        XCTAssertEqual(result.count, 2)
        let merged = try! XCTUnwrap(result.first)
        XCTAssertEqual(merged.id, codexID)
        XCTAssertEqual(merged.name, "ChatGPT + Codex")
        XCTAssertEqual(merged.bundleIdentifier, "com.openai.codex")
        XCTAssertEqual(merged.applicationURL, chatGPTURL)
        XCTAssertEqual(
            Set(merged.rootURLs.map(\.path)),
            [
                "/Users/test/.codex",
                "/Users/test/Library/Application Support/ChatGPT"
            ]
        )
        XCTAssertEqual(merged.itemIDs, [codexItemID, chatGPTItemID])
        XCTAssertEqual(merged.pluginIDs, [pluginID])
        XCTAssertEqual(merged.skillIDs, [skillID])
        XCTAssertEqual(merged.applicationAllocatedSize, 1_400)
        XCTAssertEqual(merged.supportLevel, .deep)
        XCTAssertEqual(result.last?.name, "Claude")
    }

    func testLeavesApplicationsUnchangedWhenOneFamilyMemberIsMissing() {
        let codex = application(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            roots: ["/Users/test/.codex"],
            supportLevel: .deep
        )

        XCTAssertEqual(
            AIApplicationProductFamilyMerger()
                .mergeChatGPTAndCodex(in: [codex]),
            [codex]
        )
    }

    func testSavedSnapshotProjectionMergesLegacySeparateRecords() throws {
        let codexItemID = UUID()
        let chatGPTItemID = UUID()
        let codex = application(
            name: "Codex",
            bundleIdentifier: "com.openai.codex",
            roots: ["/Users/test/.codex"],
            itemIDs: [codexItemID],
            applicationSize: 1_000,
            supportLevel: .deep
        )
        let chatGPT = application(
            name: "ChatGPT",
            bundleIdentifier: "com.openai.chat",
            applicationURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            roots: ["/Users/test/Library/Application Support/ChatGPT"],
            itemIDs: [chatGPTItemID],
            applicationSize: 1_400,
            supportLevel: .basic
        )
        let snapshot = ScanSnapshot(
            completedAt: Date(),
            volume: nil,
            items: [
                scannedItem(id: codexItemID, path: "/Users/test/.codex", size: 3_000),
                scannedItem(
                    id: chatGPTItemID,
                    path: "/Users/test/Library/Application Support/ChatGPT",
                    size: 400
                )
            ],
            applications: [],
            aiApplications: [codex, chatGPT],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = try AppSnapshotProjection.build(snapshot: snapshot)

        let merged = try XCTUnwrap(projection.developerAI.applications.only)
        XCTAssertEqual(merged.application.name, "ChatGPT + Codex")
        XCTAssertEqual(merged.dataItems.count, 2)
        XCTAssertEqual(merged.totalSize, 4_800)
    }

    private func application(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String?,
        applicationURL: URL? = nil,
        roots: [String],
        itemIDs: Set<UUID> = [],
        pluginIDs: Set<UUID> = [],
        skillIDs: Set<UUID> = [],
        applicationSize: Int64 = 0,
        supportLevel: AIApplicationSupportLevel
    ) -> AIApplicationRecord {
        AIApplicationRecord(
            id: id,
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: applicationURL,
            rootURLs: roots.map(URL.init(fileURLWithPath:)),
            itemIDs: itemIDs,
            pluginIDs: pluginIDs,
            skillIDs: skillIDs,
            applicationAllocatedSize: applicationSize,
            supportLevel: supportLevel
        )
    }

    private func scannedItem(id: UUID, path: String, size: Int64) -> ScannedItem {
        ScannedItem(
            id: id,
            url: URL(fileURLWithPath: path),
            logicalSize: size,
            allocatedSize: size,
            category: .aiData,
            risk: .sensitive,
            ownerID: nil,
            explanation: "Test AI data"
        )
    }
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
