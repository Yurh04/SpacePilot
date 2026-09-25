import AppKit
import SpacePilotCore
import SwiftUI
import XCTest
@testable import SpacePilot

@MainActor
final class AIWorkspacePresentationTests: XCTestCase {
    func testWorkspaceKeepsCompactContentAndBoundedSidebar() {
        XCTAssertEqual(AIWorkspaceLayout.pagePadding, 16)
        XCTAssertEqual(AIWorkspaceLayout.sectionSpacing, 12)
        XCTAssertEqual(AIWorkspaceLayout.fileIconSize, 24)
        XCTAssertEqual(AIWorkspaceLayout.rowPadding, 3)
        XCTAssertGreaterThanOrEqual(AIWorkspaceLayout.sidebarMinimum, 200)
        XCTAssertLessThan(AIWorkspaceLayout.sidebarMinimum, AIWorkspaceLayout.sidebarIdeal)
        XCTAssertLessThanOrEqual(AIWorkspaceLayout.sidebarMaximum, 280)
    }

    func testNavigationAndCardSymbolsExistOnMacOS() {
        let symbols = DeveloperAISidebarRow.capabilityRows.map(\.systemImage)
            + AIAgentDetailView.Tab.allCases.map(\.systemImage)
            + ["folder.badge.person.crop", "folder.fill", "folder.badge.questionmark",
               "sparkles.rectangle.stack", "heart.text.clipboard", "square.on.square",
               "point.3.connected.trianglepath.dotted", "network", "chart.bar.xaxis"]
        for symbol in symbols {
            XCTAssertNotNil(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), symbol)
        }
    }

    func testAllAssetTablesUseVisualIdentityWithoutInterceptingSelection() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for file in ["GlobalSkillsView", "GlobalPluginsView", "CLIToolsView", "MCPServersView", "OtherAIToolsView"] {
            let source = try String(contentsOf: root.appending(path: "Sources/SpacePilot/Views/DeveloperAI/\(file).swift"), encoding: .utf8)
            XCTAssertTrue(source.contains("AIAssetIdentity("), file)
            XCTAssertTrue(source.contains("AIWorkspaceHeader("), file)
            XCTAssertTrue(source.contains(".nativeTableDoubleClickReveal"), file)
            XCTAssertFalse(source.contains(".onTapGesture"), file)
        }
    }

    func testDetailFileRowsSupportDoubleClickFinderReveal() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appending(path: "Sources/SpacePilot/Views/DeveloperAI/AIAgentDetailView.swift"), encoding: .utf8)
        for target in ["file.url", "server.sourceURL", "hook.sourceURL", "item.url", "url"] {
            XCTAssertTrue(source.contains(".onDoubleClickRevealInFinder(\(target))"), target)
        }
    }

    func testMetricTileIsCompact() {
        let host = NSHostingView(rootView: AIMetricTile(title: "AI Agent", value: "18", systemImage: "sparkles").frame(width: 160))
        XCTAssertLessThanOrEqual(host.fittingSize.height, 64)
    }

    /// Render actual SwiftUI views with deterministic fixtures, without scanning a
    /// home directory, opening a visible window, or starting discovery/update work.
    /// Set SPACEPILOT_UI_SNAPSHOTS to a directory to inspect the rendered PNGs.
    func testOverviewAndDetailRenderAtCompactAndWideWidthsInBothAppearances() throws {
        for width: CGFloat in [560, 920] {
            for scheme: ColorScheme in [.light, .dark] {
                try render(overview, name: "overview", width: width, scheme: scheme)
                try render(detail, name: "agent", width: width, scheme: scheme)
            }
        }
    }

    func testCapabilityTablesRenderCompactRegularAndEmptyStates() throws {
        let servers = [MCPServerRecord(
            name: "workspace-files-and-documents", ownerDefinitionID: "codex",
            sourceURL: URL(fileURLWithPath: "/tmp/spacepilot-fixture/config.json"),
            transport: .stdio, command: nil, isEnabled: false
        )]
        let tools = [OtherAIToolRecord(
            name: "Configuration Manager", kind: .configurationManager,
            installMethod: .applicationBundle, affectedAgentIDs: ["codex"],
            url: URL(fileURLWithPath: "/tmp/spacepilot-fixture/Manager.app"), allocatedSize: 1024
        )]
        for width: CGFloat in [380, 840] {
            try render(MCPServersView(servers: servers, agents: agents, searchText: ""),
                       name: "mcp", width: width, scheme: .light)
            try render(OtherAIToolsView(tools: tools, agents: agents, searchText: ""),
                       name: "tools", width: width, scheme: .dark)
        }
        try render(MCPServersView(servers: [], agents: [], searchText: ""),
                   name: "mcp-empty", width: 560, scheme: .light)
        try render(OtherAIToolsView(tools: tools, agents: agents, searchText: "no-match"),
                   name: "tools-no-results", width: 560, scheme: .dark)
    }

    func testLongAssetIdentityFitsCompactColumn() throws {
        let view = AIAssetIdentity(
            name: "a-very-long-skill-name-with-multiple-words-and-a-project-suffix",
            subtitle: "/Users/example/Workspace/a-very-long-project/.agents/skills/design-system-review/SKILL.md",
            systemImage: "folder.fill"
        )
        let host = NSHostingView(rootView: view.frame(width: 220))
        XCTAssertLessThanOrEqual(host.fittingSize.width, 220)
        XCTAssertGreaterThanOrEqual(host.fittingSize.height, 30)
        XCTAssertLessThanOrEqual(host.fittingSize.height, 44)
    }

    private var agents: [AIAgentEntry] {
        [
            AIAgentEntry(id: "chatgpt", displayName: "ChatGPT", locality: .local,
                         formFactors: [.application, .cli], icon: .systemSymbol(name: "terminal"),
                         applicationURL: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
                         executableURL: URL(fileURLWithPath: "/usr/local/bin/codex"),
                         detectedVersion: "1.2.3", definitionIDs: ["chatgpt", "codex"]),
            AIAgentEntry(id: "claude", displayName: "Claude", locality: .local,
                         formFactors: [.application], icon: .systemSymbol(name: "sparkles")),
            AIAgentEntry(id: "remote", displayName: "Remote Agent", locality: .remote,
                         formFactors: [.cloud], icon: .systemSymbol(name: "cloud"))
        ]
    }

    private var overview: some View {
        AIManagementOverviewView(
            agents: agents, onSelectAgent: { _ in }, managementProjection: .empty,
            appCount: 3, cliCount: 7, globalSkillCount: 128, globalPluginCount: 12,
            duplication: SkillDuplicationAnalyzer.analyze(skills: []), healthFindings: [],
            mcpCount: 8, hookCount: 2, isDiscovering: false, discoveryError: nil,
            updateSummary: .empty, isCheckingUpdates: false, updateError: nil,
            onCheckUpdates: {}, onCancelUpdateCheck: {}
        )
    }

    private var detail: some View {
        AIAgentDetailView(
            detail: AIAgentDetailProjection(agent: agents[0], skills: [], plugins: []),
            mcpServers: [], hooks: [], instructionFiles: [],
            configProfile: AgentConfigProfile(
                ownerDefinitionID: "codex", sourceURL: URL(fileURLWithPath: "/tmp/config.toml"),
                model: "example-model", reasoningEffort: "high", hasCredential: true
            ),
            revealURL: agents[0].applicationURL, formFactorLabels: ["App", "CLI"]
        )
    }

    private func render<V: View>(_ view: V, name: String, width: CGFloat, scheme: ColorScheme) throws {
        let appearance = scheme == .dark ? "dark" : "light"
        let host = NSHostingView(rootView: view.environment(\.colorScheme, scheme)
            .frame(width: width, height: 900))
        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: width, height: 900)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(host.fittingSize.width, width, accuracy: 1)
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 10_000, "The workspace must not render as a blank surface")
        if let directory = ProcessInfo.processInfo.environment["SPACEPILOT_UI_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try png.write(to: url.appending(path: "\(name)-\(Int(width))-\(appearance).png"))
        }
    }
}
