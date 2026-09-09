import XCTest
@testable import SpacePilotCore

final class AIAgentStorageScannerTests: XCTestCase {
    private struct MetadataAccess: FileSystemAccess {
        let files: [String: Int64]
        var links: Set<String> = []
        var denied: Set<String> = []

        func contentsOfDirectory(at url: URL) throws -> [URL] {
            if denied.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
            let prefix = url.path + "/"
            let children = Set(files.keys.filter { $0.hasPrefix(prefix) }.map {
                String($0.dropFirst(prefix.count).split(separator: "/")[0])
            })
            return children.sorted().map { url.appending(path: $0) }
        }

        func metadata(at url: URL) throws -> FileMetadata {
            if denied.contains(url.path) { throw CocoaError(.fileReadNoPermission) }
            return FileMetadata(
                isDirectory: files[url.path] == nil,
                isRegularFile: files[url.path] != nil,
                isSymbolicLink: links.contains(url.path),
                isPackage: url.pathExtension == "app",
                logicalSize: files[url.path] ?? 0, allocatedSize: files[url.path] ?? 0,
                creationDate: nil, modificationDate: nil, resourceIdentifier: url.path
            )
        }
    }

    private func agent(_ id: String = "codex", roots: [String] = ["/fixture/.codex"]) -> AIAgentEntry {
        AIAgentEntry(
            id: id, displayName: id, locality: .local, formFactors: [.cli],
            icon: .systemSymbol(name: "terminal"),
            dataRoots: roots.map { URL(fileURLWithPath: $0) },
            configDirectories: roots.map { URL(fileURLWithPath: $0) }
        )
    }

    func testAllChildrenAppearIncludingUnknownDatabasesAndEmbeddedApps() throws {
        let files: [String: Int64] = [
            "/fixture/.codex/sessions/2026/session.jsonl": 100,
            "/fixture/.codex/logs_2.sqlite": 200,
            "/fixture/.codex/logs_2.sqlite-wal": 30,
            "/fixture/.codex/thread_history_1.sqlite": 40,
            "/fixture/.codex/history.jsonl": 5,
            "/fixture/.codex/computer-use/Helper.app/Contents/MacOS/helper": 60,
            "/fixture/.codex/cache/data": 20,
            "/fixture/.codex/new-unknown.sqlite": 15,
            "/fixture/.codex/auth.json": 4
        ]
        let snapshot = try XCTUnwrap(AIAgentStorageScanner(access: MetadataAccess(files: files))
            .scan(agents: [agent()])["codex"])
        let rows = Dictionary(uniqueKeysWithValues: snapshot.items.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(rows.count, 9)
        XCTAssertEqual(rows["logs_2.sqlite-wal"]?.category, .log)
        XCTAssertEqual(rows["thread_history_1.sqlite"]?.category, .conversation)
        XCTAssertEqual(rows["computer-use"]?.allocatedSize, 60)
        XCTAssertEqual(rows["new-unknown.sqlite"]?.category, .aiData)
        XCTAssertEqual(snapshot.items.reduce(0) { $0 + $1.allocatedSize }, files.values.reduce(0, +))
        let detail = AIAgentDetailProjection(agent: agent(), skills: [], plugins: [], storageSnapshot: snapshot)
        XCTAssertEqual(detail.totalStorageSize, detail.storageBreakdown.reduce(0) { $0 + $1.allocatedSize })
        XCTAssertEqual(detail.storageItems, snapshot.items)
    }

    func testOverlappingRootsAreNotDoubleCountedAndNestedSymlinksAreNotFollowed() throws {
        let files: [String: Int64] = [
            "/fixture/.codex/sessions/one": 100,
            "/fixture/.codex/skills/external": 8
        ]
        let access = MetadataAccess(files: files, links: ["/fixture/.codex/skills/external"])
        let snapshot = try XCTUnwrap(AIAgentStorageScanner(access: access).scan(agents: [
            agent(roots: ["/fixture/.codex", "/fixture/.codex/sessions"])
        ])["codex"])
        XCTAssertEqual(snapshot.items.count, 2)
        XCTAssertEqual(snapshot.items.reduce(0) { $0 + $1.allocatedSize }, 108)
    }

    func testEveryAgentUsesSameScannerAndPermissionFailureIsNotZeroSize() throws {
        let files: [String: Int64] = [
            "/fixture/.pi/agent/sessions/one": 99,
            "/fixture/.relay/projects/two": 123
        ]
        let snapshots = try AIAgentStorageScanner(access: MetadataAccess(
            files: files, denied: ["/fixture/.relay/projects"]
        )).scan(agents: [
            agent("pi", roots: ["/fixture/.pi/agent"]),
            agent("relay", roots: ["/fixture/.relay"])
        ])
        XCTAssertEqual(snapshots["pi"]?.items.first?.allocatedSize, 99)
        XCTAssertEqual(snapshots["relay"]?.items.first?.isSizeKnown, false)
        XCTAssertEqual(snapshots["relay"]?.coverageFailures, [.permissionDenied])
    }

    func testSkillShowsItsParentPluginNameAndSize() throws {
        let plugin = PluginRecord(
            name: "Example Plugin", version: "1.0",
            url: URL(fileURLWithPath: "/fixture/.codex/plugins/example"), source: "fixture", allocatedSize: 100,
            owner: .tool(definitionID: "codex")
        )
        let skill = SkillRecord(
            name: "Search", summary: "", url: plugin.url.appending(path: "skills/search"),
            allocatedSize: 32, scope: .pluginProvided(pluginID: "example"), visibleAgents: ["Codex"],
            parentPluginID: plugin.id, fingerprint: "", conflict: nil, managementStatus: .parentManaged
        )
        let detail = AIAgentDetailProjection(agent: agent(), skills: [skill], plugins: [plugin])
        XCTAssertEqual(detail.skills.first?.allocatedSize, 32)
        XCTAssertEqual(detail.sourcePluginName(for: skill), "Example Plugin")
    }
}
