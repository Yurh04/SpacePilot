import XCTest
@testable import SpacePilotCore

final class ViewProjectionTests: XCTestCase {
    func testAIApplicationProjectionExposesPluginSkillCount() throws {
        let skillID = UUID()
        let plugin = PluginRecord(
            name: "product-design",
            version: "1",
            url: URL(fileURLWithPath: "/tmp/plugin"),
            source: "openai-curated-remote",
            allocatedSize: 42,
            skillIDs: [skillID],
            dependencies: []
        )

        XCTAssertEqual(plugin.skillCount, 1)
    }

    func testAppSnapshotProjectionBuildsAllPageInputs() throws {
        let plugin = PluginRecord(
            name: "product-design",
            version: "0.1.52",
            url: URL(fileURLWithPath: "/tmp/product-design"),
            source: "openai-curated-remote",
            allocatedSize: 500,
            skillIDs: [],
            dependencies: []
        )
        let codex = AIApplicationRecord.fixture(pluginIDs: [plugin.id])
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [ScannedItem.fixture(allocatedSize: 100)],
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [],
            coverage: .complete,
            pluginDiagnostics: []
        )

        let projection = try AppSnapshotProjection.build(snapshot: snapshot)

        XCTAssertEqual(projection.snapshotID, snapshot.id)
        XCTAssertEqual(projection.developerAI.applications.first?.plugins.map(\.name), ["product-design"])
        XCTAssertLessThanOrEqual(projection.storage.largestItems.count, StorageProjection.itemDisplayLimit)
    }

    func testOverviewAndStorageOutputsStayBounded() {
        let items = (0..<500).map { ScannedItem.fixture(allocatedSize: Int64($0)) }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = AppSnapshotProjection(snapshot: snapshot)

        XCTAssertEqual(projection.overview.recommendations.count, 8)
        XCTAssertEqual(projection.overview.recommendations.map(\.allocatedSize), Array((492..<500).reversed()).map(Int64.init))
        XCTAssertEqual(projection.overview.reclaimableBytes, items.reduce(0) { $0 + $1.allocatedSize })
        XCTAssertEqual(projection.storage.largestItems.count, 100)
        XCTAssertLessThanOrEqual(
            projection.storage.largestItemsByCategory.values.flatMap { $0 }.count,
            StorageProjection.itemDisplayLimit * ItemCategory.allCases.count
        )
    }

    func testOverviewProjectionPreservesLimitedCoverageDetails() {
        let coverage = ScanCoverage(
            deniedPaths: [URL(fileURLWithPath: "/Users/test/Library/Mail")],
            notes: ["Full Disk Access is required"]
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: coverage
        )

        let projection = OverviewProjection(snapshot: snapshot)

        XCTAssertFalse(projection.coverage.isComplete)
        XCTAssertEqual(projection.coverage.deniedPaths, coverage.deniedPaths)
        XCTAssertEqual(projection.coverage.notes, coverage.notes)
    }

    func testOverviewProjectsDiskCapacityAndAnalyzedCategories() {
        let personal = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/archive"),
            logicalSize: 200,
            allocatedSize: 200,
            category: .personal,
            risk: .sensitive,
            explanation: "Fixture"
        )
        let cache = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/example"),
            logicalSize: 100,
            allocatedSize: 100,
            category: .cache,
            risk: .safe,
            explanation: "Fixture"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Macintosh HD",
                totalCapacity: 1_000,
                availableCapacity: 250
            ),
            items: [personal, cache],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = OverviewProjection(snapshot: snapshot)

        XCTAssertEqual(projection.totalCapacityBytes, 1_000)
        XCTAssertEqual(projection.totalUsedBytes, 750)
        XCTAssertEqual(projection.availableBytes, 250)
        XCTAssertTrue(projection.hasWholeDiskCapacity)
        XCTAssertEqual(projection.categories.map(\.category), [.personal, .cache])
        XCTAssertEqual(projection.categories.map(\.allocatedSize), [200, 100])
        XCTAssertFalse(projection.categories.contains { $0.category == .system })
        XCTAssertLessThanOrEqual(projection.categories.count, ItemCategory.allCases.count)
    }

    func testOverviewOrdersEqualSizedCategoriesByCategoryOrderRegardlessOfItemInputOrder() {
        let personal = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Documents/archive"),
            logicalSize: 100,
            allocatedSize: 100,
            category: .personal,
            risk: .sensitive,
            explanation: "Fixture"
        )
        let cache = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Library/Caches/example"),
            logicalSize: 100,
            allocatedSize: 100,
            category: .cache,
            risk: .safe,
            explanation: "Fixture"
        )
        func snapshot(items: [ScannedItem]) -> ScanSnapshot {
            ScanSnapshot(
                completedAt: .now,
                volume: nil,
                items: items,
                applications: [],
                aiApplications: [],
                plugins: [],
                skills: [],
                coverage: .complete
            )
        }

        let forward = OverviewProjection(snapshot: snapshot(items: [personal, cache]))
        let reversed = OverviewProjection(snapshot: snapshot(items: [cache, personal]))

        XCTAssertEqual(forward.categories.map(\.category), [.personal, .cache])
        XCTAssertEqual(reversed.categories.map(\.category), forward.categories.map(\.category))
    }

    func testOverviewFallsBackToAnalyzedDiskMetricsWithoutVolumeMetadata() {
        let item = ScannedItem.fixture(allocatedSize: 200)
        let application = ApplicationRecord(
            name: "Fixture",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Fixture.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [application],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = OverviewProjection(snapshot: snapshot)

        XCTAssertEqual(projection.totalCapacityBytes, 300)
        XCTAssertEqual(projection.totalUsedBytes, 300)
        XCTAssertEqual(projection.availableBytes, 0)
        XCTAssertFalse(projection.hasWholeDiskCapacity)
    }

    func testOverviewOmitsCategoriesWhoseItemsAllocateNoSpace() {
        let items = [
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/empty-cache"),
                logicalSize: 0,
                allocatedSize: 0,
                category: .cache,
                risk: .safe,
                explanation: "Fixture"
            ),
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/empty-log"),
                logicalSize: 0,
                allocatedSize: 0,
                category: .log,
                risk: .safe,
                explanation: "Fixture"
            )
        ]
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        XCTAssertTrue(OverviewProjection(snapshot: snapshot).categories.isEmpty)
    }

    func testOverviewRejectsInvalidWholeDiskCapacityMetadata() {
        let item = ScannedItem.fixture(allocatedSize: 200)
        let invalidCapacities: [(total: Int64, available: Int64)] = [
            (0, 0),
            (-1, 0),
            (1_000, -1),
            (1_000, 1_001)
        ]

        for capacity in invalidCapacities {
            let snapshot = ScanSnapshot(
                completedAt: .now,
                volume: VolumeRecord(
                    url: URL(fileURLWithPath: "/"),
                    name: "Invalid",
                    totalCapacity: capacity.total,
                    availableCapacity: capacity.available
                ),
                items: [item],
                applications: [],
                aiApplications: [],
                plugins: [],
                skills: [],
                coverage: .complete
            )
            let projection = OverviewProjection(snapshot: snapshot)

            XCTAssertFalse(
                projection.hasWholeDiskCapacity,
                "Accepted total \(capacity.total), available \(capacity.available)"
            )
            XCTAssertEqual(projection.totalCapacityBytes, 200)
            XCTAssertEqual(projection.totalUsedBytes, 200)
            XCTAssertEqual(projection.availableBytes, 0)
        }
    }

    func testDeveloperAIProjectionAggregatesIndexedCollectionsWithoutDoubleCountingPluginSkills() throws {
        let pluginID = UUID()
        let childSkill = SkillRecord.fixture(allocatedSize: 40, parentPluginID: pluginID)
        let standaloneSkill = SkillRecord.fixture(allocatedSize: 60)
        let plugin = PluginRecord(
            id: pluginID,
            name: "plugin",
            version: "1",
            url: URL(fileURLWithPath: "/tmp/plugin"),
            source: "fixture",
            allocatedSize: 500,
            skillIDs: [childSkill.id]
        )
        let item = ScannedItem.fixture(allocatedSize: 100)
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            itemIDs: [item.id],
            pluginIDs: [plugin.id],
            skillIDs: [childSkill.id, standaloneSkill.id],
            applicationAllocatedSize: 10
        )
        let developerItem = ScannedItem(
            url: URL(fileURLWithPath: "/tmp/developer"),
            logicalSize: 200,
            allocatedSize: 200,
            category: .developer,
            risk: .safe,
            explanation: "Fixture"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [developerItem, item],
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [childSkill, standaloneSkill],
            coverage: .complete,
            pluginDiagnostics: ["Invalid manifest"]
        )

        let projection = DeveloperAIProjection(snapshot: snapshot)
        let application = try XCTUnwrap(projection.applications.first)

        XCTAssertEqual(projection.developerBytes, 200)
        XCTAssertEqual(projection.pluginDiagnostics, ["Invalid manifest"])
        XCTAssertEqual(application.dataItems.map(\.id), [item.id])
        XCTAssertEqual(application.plugins.map(\.id), [plugin.id])
        XCTAssertEqual(Set(application.skills.map(\.id)), [childSkill.id, standaloneSkill.id])
        XCTAssertEqual(application.totalSize, 670)
        XCTAssertEqual(
            application.storageComponents,
            [
                AIStorageComponentProjection(category: .plugin, allocatedSize: 500),
                AIStorageComponentProjection(category: .cache, allocatedSize: 100),
                AIStorageComponentProjection(category: .skill, allocatedSize: 60),
                AIStorageComponentProjection(category: .application, allocatedSize: 10)
            ]
        )
    }

    func testDeveloperAIProjectionAssignsCodexManagedBytesToExactlyOneComponent() throws {
        let pluginID = UUID()
        let pluginRoot = "/Users/test/.codex/plugins/cache/openai-curated-remote/product-design/0.1.52"
        let pluginSkill = SkillRecord(
            name: "product-design-index",
            summary: "Fixture plugin skill",
            url: URL(fileURLWithPath: "\(pluginRoot)/skills/index"),
            allocatedSize: 200,
            scope: .pluginProvided(pluginID: pluginID.uuidString),
            visibleAgents: ["Codex"],
            parentPluginID: pluginID,
            fingerprint: "plugin-skill",
            conflict: nil,
            managementStatus: .parentManaged
        )
        let standaloneSkill = SkillRecord(
            name: "codex-helper",
            summary: "Fixture standalone skill",
            url: URL(fileURLWithPath: "/Users/test/.codex/skills/codex-helper"),
            allocatedSize: 300,
            scope: .agentSpecific(agent: "Codex"),
            visibleAgents: ["Codex"],
            parentPluginID: nil,
            fingerprint: "standalone-skill",
            conflict: nil,
            managementStatus: .standalone
        )
        let plugin = PluginRecord(
            id: pluginID,
            name: "product-design",
            version: "0.1.52",
            url: URL(fileURLWithPath: pluginRoot),
            source: "openai-curated-remote",
            allocatedSize: 700,
            skillIDs: [pluginSkill.id]
        )
        let items = [
            ScannedItem.fixture(path: "/Users/test/.codex/sessions/session.json", allocatedSize: 100),
            ScannedItem.fixture(path: "\(pluginRoot)/.codex-plugin/plugin.json", allocatedSize: 500),
            ScannedItem.fixture(path: "\(pluginRoot)/skills/index/SKILL.md", allocatedSize: 200),
            ScannedItem.fixture(path: "/Users/test/.codex/skills/codex-helper/SKILL.md", allocatedSize: 300),
            // This is not beneath `codex-helper`; component-safe matching must retain it.
            ScannedItem.fixture(path: "/Users/test/.codex/skills/codex-helper-backup/cache.db", allocatedSize: 70)
        ]
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            itemIDs: Set(items.map(\.id)),
            pluginIDs: [plugin.id],
            skillIDs: [pluginSkill.id, standaloneSkill.id],
            applicationAllocatedSize: 10
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [pluginSkill, standaloneSkill],
            coverage: .complete
        )

        let application = try XCTUnwrap(DeveloperAIProjection(snapshot: snapshot).applications.first)

        XCTAssertEqual(application.dataItems.count, 5, "Managed rows remain searchable and visible")
        XCTAssertEqual(application.plugins.reduce(0) { $0 + $1.allocatedSize }, 700)
        XCTAssertEqual(
            application.skills.filter { $0.parentPluginID == nil }.reduce(0) { $0 + $1.allocatedSize },
            300
        )
        XCTAssertEqual(application.totalSize, 1_180, "10 app + 170 generic + 700 plugin + 300 skill")
        XCTAssertEqual(
            application.storageComponents.reduce(0) { $0 + $1.allocatedSize },
            application.totalSize
        )
        XCTAssertEqual(
            application.storageComponents.first {
                $0.category == .plugin
            }?.allocatedSize,
            700
        )
    }

    func testDeveloperAIProjectionCanonicalizesSymlinkedManagedRoots() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let canonicalPluginRoot = temporaryRoot.appending(path: "real/plugin", directoryHint: .isDirectory)
        let symlinkedPluginRoot = temporaryRoot.appending(path: "alias-plugin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: canonicalPluginRoot, withIntermediateDirectories: true)
        let manifestURL = canonicalPluginRoot.appending(path: ".codex-plugin/plugin.json")
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: manifestURL)
        try FileManager.default.createSymbolicLink(
            at: symlinkedPluginRoot,
            withDestinationURL: canonicalPluginRoot
        )
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let plugin = PluginRecord(
            name: "symlinked",
            version: "1",
            url: symlinkedPluginRoot,
            source: "fixture",
            allocatedSize: 80
        )
        let managedItem = ScannedItem.fixture(
            path: manifestURL.resolvingSymlinksInPath().path,
            allocatedSize: 80
        )
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            itemIDs: [managedItem.id],
            pluginIDs: [plugin.id]
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [managedItem],
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [],
            coverage: .complete
        )

        let application = try XCTUnwrap(DeveloperAIProjection(snapshot: snapshot).applications.first)

        XCTAssertEqual(application.dataItems.map(\.id), [managedItem.id])
        XCTAssertEqual(application.totalSize, 80)
    }

    func testRealScannersCountHiddenManagedFilesExactlyOnceInProjection() async throws {
        let fixture = try PluginFixture.make(
            name: "product-design",
            version: "0.1.52",
            skillNames: ["index"]
        )
        let pluginManifest = fixture.root.appending(path: ".codex-plugin/plugin.json")
        let pluginSkillManifest = fixture.root.appending(path: "skills/index/SKILL.md")
        let hiddenPluginFile = fixture.root.appending(path: ".plugin-state")
        let hiddenPluginSkillFile = fixture.root.appending(path: "skills/index/.skill-state")
        try Data(repeating: 1, count: 8_192).write(to: hiddenPluginFile)
        try Data(repeating: 2, count: 12_288).write(to: hiddenPluginSkillFile)

        let standaloneSkillRoot = fixture.tree.url.appending(
            path: ".codex/skills/local-helper",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: standaloneSkillRoot, withIntermediateDirectories: true)
        let standaloneManifest = standaloneSkillRoot.appending(path: "SKILL.md")
        let hiddenStandaloneFile = standaloneSkillRoot.appending(path: ".local-state")
        try Data("---\nname: local-helper\ndescription: Local helper\n---\nInstructions".utf8)
            .write(to: standaloneManifest)
        try Data(repeating: 3, count: 16_384).write(to: hiddenStandaloneFile)

        let outsideFile = fixture.tree.url.appending(path: "outside.bin")
        try Data(repeating: 4, count: 32_768).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appending(path: "external-link"),
            withDestinationURL: outsideFile
        )

        let pluginResult = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [fixture.root])
        let standaloneSkills = try await SkillScanner().scan(roots: [SkillRoot(
            url: standaloneSkillRoot.deletingLastPathComponent(),
            scope: .agentSpecific(agent: "Codex")
        )])
        let plugin = try XCTUnwrap(pluginResult.plugins.first)
        let pluginSkill = try XCTUnwrap(pluginResult.skills.first)
        let standaloneSkill = try XCTUnwrap(standaloneSkills.first)

        func allocatedSize(of url: URL) throws -> Int64 {
            let values = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return Int64(try XCTUnwrap(values.totalFileAllocatedSize))
        }
        let pluginFiles = [
            pluginManifest, pluginSkillManifest, hiddenPluginFile, hiddenPluginSkillFile
        ]
        let standaloneFiles = [standaloneManifest, hiddenStandaloneFile]
        let expectedPluginBytes = try pluginFiles.reduce(Int64(0)) {
            $0 + (try allocatedSize(of: $1))
        }
        let expectedPluginSkillBytes = try [pluginSkillManifest, hiddenPluginSkillFile]
            .reduce(Int64(0)) { $0 + (try allocatedSize(of: $1)) }
        let expectedStandaloneBytes = try standaloneFiles.reduce(Int64(0)) {
            $0 + (try allocatedSize(of: $1))
        }

        XCTAssertEqual(plugin.allocatedSize, expectedPluginBytes)
        XCTAssertEqual(pluginSkill.allocatedSize, expectedPluginSkillBytes)
        XCTAssertEqual(standaloneSkill.allocatedSize, expectedStandaloneBytes)

        let ownedFiles = pluginFiles + standaloneFiles
        let items = try ownedFiles.map { url in
            ScannedItem.fixture(path: url.path, allocatedSize: try allocatedSize(of: url))
        }
        let codex = AIApplicationRecord.fixture(
            name: "Codex",
            itemIDs: Set(items.map(\.id)),
            pluginIDs: [plugin.id],
            skillIDs: [pluginSkill.id, standaloneSkill.id]
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [codex],
            plugins: [plugin],
            skills: [pluginSkill, standaloneSkill],
            coverage: .complete
        )

        let application = try XCTUnwrap(DeveloperAIProjection(snapshot: snapshot).applications.first)
        let managedPathSearch = try AIApplicationQueryProjection.build(
            application: application,
            query: ".plugin-state"
        )

        XCTAssertEqual(application.dataItems.count, ownedFiles.count)
        XCTAssertEqual(application.totalSize, expectedPluginBytes + expectedStandaloneBytes)
        XCTAssertEqual(snapshot.uniqueAIAllocatedSize, expectedPluginBytes + expectedStandaloneBytes)
        XCTAssertEqual(managedPathSearch.dataItems.map(\.url), [hiddenPluginFile])
    }

    func testAIApplicationTabsRemainNestedUnderSelectedApplication() {
        XCTAssertEqual(AIApplicationTab.allCases.map(\.rawValue), [
            "overview", "dataStorage", "plugins", "skills"
        ])
    }

    func testOverviewRecommendationsExcludeSensitiveAndManagedByDefault() {
        let items = RiskLevel.allCases.map { risk in
            ScannedItem.fixture(risk: risk, allocatedSize: 100)
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = OverviewProjection(snapshot: snapshot)

        XCTAssertTrue(projection.preselectedRecommendations.allSatisfy { $0.risk == .safe })
        XCTAssertEqual(projection.preselectedRecommendations.count, 1)
    }

    func testCategoryTotalsDoNotDoubleCountItems() {
        let item = ScannedItem.fixture(allocatedSize: 256)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.categories.reduce(0) { $0 + $1.allocatedSize }, 256)
    }

    func testStorageProjectionPublishesDiskMetricsAndCategoryItems() {
        let oldCache = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/old",
            allocatedSize: 300,
            modificationDate: .distantPast
        )
        let recentCache = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/recent",
            allocatedSize: 200,
            modificationDate: .now
        )
        let developer = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/Library/Developer/build"),
            logicalSize: 100,
            allocatedSize: 100,
            modificationDate: .distantPast,
            category: .developer,
            risk: .safe,
            explanation: "Fixture"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Macintosh HD",
                totalCapacity: 2_000,
                availableCapacity: 800
            ),
            items: [recentCache, developer, oldCache],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.totalCapacity, 2_000)
        XCTAssertEqual(projection.usedBytes, 1_200)
        XCTAssertEqual(projection.availableBytes, 800)
        XCTAssertEqual(projection.analyzedBytes, 600)
        XCTAssertEqual(projection.items(category: .cache, oldOnly: false).map(\.id), [
            oldCache.id, recentCache.id
        ])
        XCTAssertEqual(projection.items(category: .cache, oldOnly: true).map(\.id), [
            oldCache.id
        ])
        XCTAssertEqual(projection.items(category: .developer, oldOnly: false).map(\.id), [
            developer.id
        ])
    }

    func testStorageProjectionMergesResidualVolumeBytesIntoExistingSystemCategory() {
        let systemItem = ScannedItem(
            url: URL(fileURLWithPath: "/System/Library/system-data"),
            logicalSize: 200,
            allocatedSize: 200,
            modificationDate: .distantPast,
            category: .system,
            risk: .managed,
            explanation: "System data"
        )
        let cacheItem = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/app/cache",
            allocatedSize: 400,
            modificationDate: Date.distantPast.addingTimeInterval(1)
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Macintosh HD",
                totalCapacity: 2_000,
                availableCapacity: 1_000
            ),
            items: [systemItem, cacheItem],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)
        let systemSummaries = projection.categories.filter { $0.category == .system }

        XCTAssertEqual(systemSummaries.count, 1)
        XCTAssertEqual(Set(projection.categories.map(\.id)).count, projection.categories.count)
        XCTAssertEqual(systemSummaries.first?.allocatedSize, 600)
        XCTAssertEqual(systemSummaries.first?.itemCount, 1)
        XCTAssertEqual(projection.categories.map(\.category), [.system, .cache])
        XCTAssertEqual(projection.categories.reduce(0) { $0 + $1.allocatedSize }, 1_000)
        XCTAssertEqual(projection.largestItems.map(\.id), [cacheItem.id, systemItem.id])
        XCTAssertEqual(projection.oldItems.map(\.id), [systemItem.id, cacheItem.id])
    }

    func testStorageProjectionDoesNotAddResidualWhenClassifiedBytesCoverUsedVolume() {
        let systemItem = ScannedItem(
            url: URL(fileURLWithPath: "/System/Library/system-data"),
            logicalSize: 600,
            allocatedSize: 600,
            category: .system,
            risk: .managed,
            explanation: "System data"
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Macintosh HD",
                totalCapacity: 1_000,
                availableCapacity: 500
            ),
            items: [systemItem],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.categories.count, 1)
        XCTAssertEqual(projection.categories.first?.category, .system)
        XCTAssertEqual(projection.categories.first?.allocatedSize, 600)
        XCTAssertEqual(projection.categories.first?.itemCount, 1)
    }

    func testStorageProjectionCreatesSystemCategoryForResidualWithoutSystemItems() {
        let cacheItem = ScannedItem.fixture(allocatedSize: 400)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Macintosh HD",
                totalCapacity: 1_000,
                availableCapacity: 400
            ),
            items: [cacheItem],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = StorageProjection(snapshot: snapshot)
        let systemSummaries = projection.categories.filter { $0.category == .system }

        XCTAssertEqual(systemSummaries.count, 1)
        XCTAssertEqual(systemSummaries.first?.allocatedSize, 200)
        XCTAssertEqual(systemSummaries.first?.itemCount, 0)
        XCTAssertEqual(Set(projection.categories.map(\.id)).count, projection.categories.count)
        XCTAssertEqual(projection.categories.reduce(0) { $0 + $1.allocatedSize }, 600)
    }

    func testOldItemsUseMetadataOnlyCutoff() {
        let old = ScannedItem.fixture(modificationDate: .distantPast)
        let recent = ScannedItem.fixture(modificationDate: .now)
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [old, recent],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        XCTAssertEqual(StorageProjection(snapshot: snapshot).oldItems.map(\.id), [old.id])
    }

    func testStorageProjectionRetainsExactlyLargestItemsInDescendingOrder() {
        let adversarialSizes = (0..<50).flatMap { [$0, 100 - $0] } + [50]
        let items = adversarialSizes.map { size in
            ScannedItem.fixture(allocatedSize: Int64(size))
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        let expectedItems = items
            .sorted { $0.allocatedSize > $1.allocatedSize }
            .prefix(StorageProjection.itemDisplayLimit)

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.largestItems.map(\.id), expectedItems.map(\.id))
        XCTAssertEqual(
            projection.largestItems.map(\.allocatedSize),
            Array((1...100).reversed()).map(Int64.init)
        )
    }

    func testStorageProjectionRetainsExactlyOldestItemsInAscendingOrder() {
        let adversarialOffsets = (0..<50).flatMap { [$0, 100 - $0] } + [50]
        let items = adversarialOffsets.map { offset in
            ScannedItem.fixture(
                allocatedSize: Int64(offset),
                modificationDate: Date.distantPast.addingTimeInterval(TimeInterval(offset))
            )
        }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        let expectedItems = items
            .sorted { ($0.modificationDate ?? .distantFuture) < ($1.modificationDate ?? .distantFuture) }
            .prefix(StorageProjection.itemDisplayLimit)

        let projection = StorageProjection(snapshot: snapshot)

        XCTAssertEqual(projection.oldItems.map(\.id), expectedItems.map(\.id))
        XCTAssertEqual(projection.oldItems.map(\.modificationDate), expectedItems.map(\.modificationDate))
    }

    func testApplicationListProjectionAggregatesRelatedSizesBeforeSorting() {
        let largerID = UUID()
        let smallerID = UUID()
        let larger = ApplicationRecord(
            id: largerID,
            name: "Larger",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Larger.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let smaller = ApplicationRecord(
            id: smallerID,
            name: "Smaller",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Smaller.app"),
            executableURL: nil,
            allocatedSize: 200
        )
        let items = [
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/larger-cache"),
                logicalSize: 900,
                allocatedSize: 900,
                category: .cache,
                risk: .safe,
                ownerID: largerID,
                explanation: "Fixture"
            ),
            ScannedItem(
                url: URL(fileURLWithPath: "/tmp/unowned"),
                logicalSize: 10_000,
                allocatedSize: 10_000,
                category: .cache,
                risk: .safe,
                explanation: "Fixture"
            )
        ]
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [smaller, larger],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = ApplicationListProjection(snapshot: snapshot, searchText: "")

        XCTAssertEqual(projection.applications.map(\.id), [largerID, smallerID])
        XCTAssertEqual(projection.totalSize(for: largerID), 1_000)
        XCTAssertEqual(projection.totalSize(for: smallerID), 200)
    }

    func testApplicationListProjectionCountsSharedAssociatedAIDataOnce() {
        let applicationID = UUID()
        let aiOwnerID = UUID()
        let sharedData = ScannedItem(
            url: URL(fileURLWithPath: "/Users/test/.codex/sessions"),
            logicalSize: 2_800,
            allocatedSize: 2_800,
            category: .conversation,
            risk: .sensitive,
            ownerID: aiOwnerID,
            explanation: "Codex data"
        )
        let associations = (0..<2).map { _ in
            ArtifactAssociation(
                itemID: sharedData.id,
                applicationID: applicationID,
                evidence: .knownRule,
                confidence: .high,
                risk: .sensitive,
                ownership: .shared
            )
        }
        let application = ApplicationRecord(
            id: applicationID,
            name: "ChatGPT",
            bundleIdentifier: "com.openai.codex",
            version: "1",
            url: URL(fileURLWithPath: "/Applications/ChatGPT.app"),
            executableURL: nil,
            allocatedSize: 1_400,
            associations: associations
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [sharedData],
            applications: [application],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = ApplicationListProjection(
            snapshot: snapshot,
            searchText: ""
        )

        XCTAssertEqual(
            projection.totalSize(for: applicationID),
            4_200
        )
    }

    func testApplicationListProjectionFiltersPreviouslyAggregatedApplications() {
        let alpha = ApplicationRecord(
            name: "Alpha",
            bundleIdentifier: nil,
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Alpha.app"),
            executableURL: nil,
            allocatedSize: 100
        )
        let beta = ApplicationRecord(
            name: "Beta",
            bundleIdentifier: "com.example.beta",
            version: nil,
            url: URL(fileURLWithPath: "/Applications/Beta.app"),
            executableURL: nil,
            allocatedSize: 200
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [alpha, beta],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let projection = ApplicationListProjection(snapshot: snapshot, searchText: "ignored")

        XCTAssertEqual(projection.applications.map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(projection.filtered(by: "alp").map(\.id), [alpha.id])
        XCTAssertEqual(projection.filtered(by: "EXAMPLE.BETA").map(\.id), [beta.id])
        XCTAssertEqual(projection.filtered(by: "Applications/Beta").map(\.id), [beta.id])
        XCTAssertEqual(projection.filtered(by: "   ").map(\.id), [beta.id, alpha.id])
        XCTAssertEqual(projection.filtered(by: "").map(\.id), [beta.id, alpha.id])
    }

    func testApplicationProjectionPairsAssociationsWithIndexedItems() throws {
        let applicationID = UUID()
        let item = ScannedItem.fixture(
            path: "/Users/test/Library/Caches/Example/cache.db",
            risk: .safe,
            allocatedSize: 4_096
        )
        let association = ArtifactAssociation(
            itemID: item.id,
            applicationID: applicationID,
            evidence: .exactBundleIdentifier,
            confidence: .high,
            risk: .safe,
            ownership: .owned
        )
        let missingAssociation = ArtifactAssociation(
            itemID: UUID(),
            applicationID: applicationID,
            evidence: .vendorAndNameMatch,
            confidence: .low,
            risk: .sensitive,
            ownership: .possible
        )
        let application = ApplicationRecord(
            id: applicationID,
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "1",
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            executableURL: nil,
            allocatedSize: 1_024,
            associations: [missingAssociation, association]
        )
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [item],
            applications: [application],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let result = try XCTUnwrap(ApplicationListProjection(snapshot: snapshot, searchText: "").applications.first)
        let pair = try XCTUnwrap(result.associations.first)

        XCTAssertEqual(result.application.id, applicationID)
        XCTAssertEqual(result.associations.count, 1)
        XCTAssertEqual(pair.association.id, association.id)
        XCTAssertEqual(pair.item.id, item.id)
        XCTAssertEqual(pair.item.url.lastPathComponent, "cache.db")
        XCTAssertEqual(pair.item.allocatedSize, 4_096)
    }

    func testAIApplicationQueryProjectionFiltersDataAndSkillsWithoutChangingEmptyQuery() throws {
        let matchingItem = ScannedItem.fixture(path: "/Users/test/.codex/data.json")
        let otherItem = ScannedItem.fixture(path: "/Users/test/.claude/data.json")
        let matchingSkill = SkillRecord(
            name: "Codex Helper",
            summary: "Fixture",
            url: URL(fileURLWithPath: "/Users/test/.agents/skills/codex-helper"),
            allocatedSize: 1,
            scope: .sharedAgents,
            visibleAgents: ["Codex"],
            parentPluginID: nil,
            fingerprint: "codex",
            conflict: nil,
            managementStatus: .standalone
        )
        let otherSkill = SkillRecord(
            name: "Claude Helper",
            summary: "Fixture",
            url: URL(fileURLWithPath: "/Users/test/.agents/skills/claude-helper"),
            allocatedSize: 1,
            scope: .sharedAgents,
            visibleAgents: ["Claude"],
            parentPluginID: nil,
            fingerprint: "claude",
            conflict: nil,
            managementStatus: .standalone
        )
        let application = AIApplicationProjection(
            application: .fixture(),
            totalSize: 2,
            dataItems: [matchingItem, otherItem],
            plugins: [],
            skills: [matchingSkill, otherSkill]
        )

        let filtered = try AIApplicationQueryProjection.build(application: application, query: "CoDeX")
        let unfiltered = try AIApplicationQueryProjection.build(application: application, query: "")

        XCTAssertEqual(filtered.applicationID, application.id)
        XCTAssertEqual(filtered.query, "CoDeX")
        XCTAssertEqual(filtered.dataItems.map(\.id), [matchingItem.id])
        XCTAssertEqual(filtered.skills.map(\.id), [matchingSkill.id])
        XCTAssertEqual(unfiltered.dataItems.map(\.id), application.dataItems.map(\.id))
        XCTAssertEqual(unfiltered.skills.map(\.id), application.skills.map(\.id))
    }

    func testAppSnapshotProjectionBuildThrowsWhenTaskIsCancelled() async {
        let items = (0..<10_000).map { ScannedItem.fixture(allocatedSize: Int64($0)) }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: items,
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )

        let observedCancellation = await Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try AppSnapshotProjection.build(snapshot: snapshot)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value

        XCTAssertTrue(observedCancellation)
    }

    func testCancellationAwareOrderingThrowsAtPeriodicMergeCheckpoint() {
        let checker = DeterministicCancellationChecker(cancelAtCheck: 3)
        let values = Array((0..<4_096).reversed())

        XCTAssertThrowsError(try ProjectionCancellationAwareOrdering.sorted(
            values,
            by: checker.areInIncreasingOrder,
            checkCancellation: checker.check
        )) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(checker.checkCount, 3)
        XCTAssertGreaterThan(checker.comparisonCount, 0)
        XCTAssertLessThan(checker.comparisonCount, values.count / 2)
    }
}

private final class DeterministicCancellationChecker: @unchecked Sendable {
    private let lock = NSLock()
    private let cancelAtCheck: Int
    private var storedCheckCount = 0
    private var storedComparisonCount = 0

    init(cancelAtCheck: Int) {
        self.cancelAtCheck = cancelAtCheck
    }

    var checkCount: Int {
        lock.withLock { storedCheckCount }
    }

    var comparisonCount: Int {
        lock.withLock { storedComparisonCount }
    }

    func check() throws {
        try lock.withLock {
            storedCheckCount += 1
            if storedCheckCount == cancelAtCheck {
                throw CancellationError()
            }
        }
    }

    func areInIncreasingOrder(_ lhs: Int, _ rhs: Int) -> Bool {
        lock.withLock { storedComparisonCount += 1 }
        return lhs < rhs
    }
}
