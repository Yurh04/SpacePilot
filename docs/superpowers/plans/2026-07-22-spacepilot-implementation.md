# SpacePilot Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native, local-only macOS utility that analyzes internal storage, safely uninstalls applications, and explains Codex and Claude data, Plugins, and Skills.

**Architecture:** A SwiftPM workspace contains a reusable `SpacePilotCore` library and a SwiftUI `SpacePilot` executable. Read-only scanner services produce immutable snapshots stored in SQLite; a separate cleanup planner and executor revalidate explicit user-approved actions before moving files to the Trash. The app uses a native sidebar-detail layout with a small `@Observable` app model.

**Tech Stack:** Swift 6, SwiftUI, Observation, AppKit interop, Foundation, CryptoKit, SQLite3, XCTest, Swift Package Manager.

## Global Constraints

- Minimum OS: macOS 15 Sequoia.
- CPU: Apple Silicon only.
- All analysis is local; do not upload paths, content, logs, conversations, credentials, or scan results.
- Scan only the internal Mac volume in the first version.
- Scanners are read-only; mutations pass through an immutable cleanup plan and explicit confirmation.
- Skills never move between shared, Codex, and Claude directories.
- Plugin caches and system-managed assets are not directly mutated.
- Codex and Claude receive deep adapters; other AI applications receive basic footprint reporting.
- The UI uses a native sidebar, semantic colors, one blue accent, minimal card chrome, and automatic Light/Dark mode.
- Tests may mutate only freshly created and explicitly validated temporary directories.
- No third-party package dependency is added without a design-spec amendment.

---

## File Map

```text
Package.swift                                  SwiftPM products and targets
Sources/SpacePilot/App/                        SwiftUI entry point and application state
Sources/SpacePilot/Views/                      Native sidebar and feature views
Sources/SpacePilotCore/Models/                 Immutable domain value types
Sources/SpacePilotCore/Scanning/               Scan protocols, coordination, filesystem traversal
Sources/SpacePilotCore/Applications/           App inventory and artifact association
Sources/SpacePilotCore/AI/                     AI app registry, Codex and Claude adapters
Sources/SpacePilotCore/Skills/                 Skill discovery, scope, parsing, conflict detection
Sources/SpacePilotCore/Plugins/                Plugin manifests and parent-child relationships
Sources/SpacePilotCore/Cleanup/                Safety policy, plan building, Trash execution
Sources/SpacePilotCore/Persistence/             SQLite snapshot and cleanup history store
Sources/SpacePilotCore/Permissions/             Scan coverage and System Settings handoff
Sources/SpacePilotCore/Support/                 Formatting, hashing, and URL helpers
Tests/SpacePilotCoreTests/                      Unit, fixture, and integration tests
Tests/SpacePilotCoreTests/Fixtures/             Reusable disposable trees, model builders, and test doubles
script/build_and_run.sh                         Single build, bundle, launch, and verify entry point
.codex/environments/environment.toml            Codex Run action
```

---

### Task 1: Package, App Shell, and Run Contract

**Files:**
- Create: `Package.swift`
- Create: `Sources/SpacePilot/App/SpacePilotApp.swift`
- Create: `Sources/SpacePilot/App/AppModel.swift`
- Create: `Sources/SpacePilot/Views/AppRootView.swift`
- Create: `Sources/SpacePilotCore/Models/NavigationDestination.swift`
- Create: `Tests/SpacePilotCoreTests/PackageSmokeTests.swift`
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

**Interfaces:**
- Produces: `NavigationDestination`, `AppModel`, executable product `SpacePilot`, library product `SpacePilotCore`.
- Consumes: no earlier task.

- [ ] **Step 1: Write the package smoke test**

```swift
import XCTest
@testable import SpacePilotCore

final class PackageSmokeTests: XCTestCase {
    func testNavigationDestinationsHaveStableTitles() {
        XCTAssertEqual(NavigationDestination.allCases.map(\.title), [
            "Overview", "Storage", "Applications", "Developer & AI", "Cleanup History"
        ])
    }
}
```

- [ ] **Step 2: Run the test and verify the package is missing**

Run: `swift test --filter PackageSmokeTests`

Expected: FAIL because `Package.swift` or `NavigationDestination` does not exist.

- [ ] **Step 3: Create the package and minimal app shell**

`Package.swift` defines:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpacePilot",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SpacePilotCore", targets: ["SpacePilotCore"]),
        .executable(name: "SpacePilot", targets: ["SpacePilot"])
    ],
    targets: [
        .target(name: "SpacePilotCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "SpacePilot", dependencies: ["SpacePilotCore"]),
        .testTarget(name: "SpacePilotCoreTests", dependencies: ["SpacePilotCore"])
    ],
    swiftLanguageModes: [.v6]
)
```

`NavigationDestination` is:

```swift
public enum NavigationDestination: String, CaseIterable, Identifiable, Sendable {
    case overview, storage, applications, developerAI, history
    public var id: Self { self }
    public var title: String {
        switch self {
        case .overview: "Overview"
        case .storage: "Storage"
        case .applications: "Applications"
        case .developerAI: "Developer & AI"
        case .history: "Cleanup History"
        }
    }
    public var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .storage: "internaldrive"
        case .applications: "square.grid.2x2"
        case .developerAI: "sparkles.rectangle.stack"
        case .history: "clock.arrow.circlepath"
        }
    }
}
```

`SpacePilotApp` installs an `NSApplicationDelegate`, uses `WindowGroup`, and presents a `Settings` scene. `AppRootView` is a `NavigationSplitView` with native sidebar rows and an initial detail view that names the selected destination. `AppModel` owns the selected destination.

- [ ] **Step 4: Add the canonical build-and-run contract**

Create `script/build_and_run.sh` from the Build macOS run-button contract with:

```bash
APP_NAME="SpacePilot"
BUNDLE_ID="com.yurunhao.SpacePilot"
MIN_SYSTEM_VERSION="15.0"
```

The script kills an existing process, runs `swift build`, stages `dist/SpacePilot.app`, writes a complete minimal `Info.plist`, launches with `/usr/bin/open -n`, and supports `--debug`, `--logs`, `--telemetry`, and `--verify`. Make it executable.

Create `.codex/environments/environment.toml`:

```toml
# THIS IS AUTOGENERATED. DO NOT EDIT MANUALLY
version = 1
name = "SpacePilot"

[setup]
script = ""

[[actions]]
name = "Run"
icon = "run"
command = "./script/build_and_run.sh"
```

- [ ] **Step 5: Build and verify the shell**

Run: `swift test && ./script/build_and_run.sh --verify`

Expected: tests PASS; `dist/SpacePilot.app` exists; `pgrep -x SpacePilot` succeeds.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests script .codex
git commit -m "feat: scaffold native SpacePilot app"
```

---

### Task 2: Domain Models and Stable Aggregation

**Files:**
- Create: `Sources/SpacePilotCore/Models/ScannedItem.swift`
- Create: `Sources/SpacePilotCore/Models/ApplicationRecord.swift`
- Create: `Sources/SpacePilotCore/Models/AIApplicationRecord.swift`
- Create: `Sources/SpacePilotCore/Models/PluginRecord.swift`
- Create: `Sources/SpacePilotCore/Models/SkillRecord.swift`
- Create: `Sources/SpacePilotCore/Models/ScanSnapshot.swift`
- Create: `Sources/SpacePilotCore/Models/CleanupModels.swift`
- Create: `Sources/SpacePilotCore/Support/ByteCount.swift`
- Create: `Tests/SpacePilotCoreTests/ModelAggregationTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/ModelFixtures.swift`

**Interfaces:**
- Produces: `ScannedItem`, `ApplicationRecord`, `AIApplicationRecord`, `PluginRecord`, `SkillRecord`, `ScanSnapshot`, `CleanupPlan`, `CleanupTransaction`.
- Consumes: `NavigationDestination` only for UI, not core models.

- [ ] **Step 1: Write aggregation tests**

```swift
func testSharedSkillIsNotDoubleCounted() {
    let sharedID = UUID()
    let codex = AIApplicationRecord.fixture(skillIDs: [sharedID], allocatedSize: 100)
    let claude = AIApplicationRecord.fixture(skillIDs: [sharedID], allocatedSize: 200)
    let skill = SkillRecord.fixture(id: sharedID, allocatedSize: 50, scope: .sharedAgents)
    let snapshot = ScanSnapshot.fixture(aiApplications: [codex, claude], skills: [skill])
    XCTAssertEqual(snapshot.uniqueAIAllocatedSize, 350)
}

func testRiskSortPlacesSensitiveLast() {
    XCTAssertEqual(RiskLevel.allCases.sorted().map(\.rawValue), [
        "safe", "rebuildable", "sensitive", "managed"
    ])
}
```

- [ ] **Step 2: Run and verify missing types**

Run: `swift test --filter ModelAggregationTests`

Expected: FAIL with missing model symbols.

- [ ] **Step 3: Implement immutable Sendable models**

Use value types with explicit IDs and Codable conformance. Required enums:

```swift
public enum RiskLevel: String, Codable, CaseIterable, Comparable, Sendable {
    case safe, rebuildable, sensitive, managed
    public static func < (lhs: Self, rhs: Self) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }
}

public enum SkillScope: Codable, Hashable, Sendable {
    case sharedAgents
    case agentSpecific(agent: String)
    case pluginProvided(pluginID: String)
    case systemManaged
}

public enum ItemCategory: String, Codable, Sendable {
    case application, personal, developer, aiData, cache, log, conversation
    case model, plugin, skill, system, unclassified
}
```

`ScanSnapshot.uniqueAIAllocatedSize` sums AI-owned item IDs and Skill IDs through a `Set<UUID>` before summing sizes. `ByteCount.string(_:)` uses `ByteCountFormatter` with file style.

Create `ModelFixtures.swift` with deterministic `fixtureID`, `ScannedItem.fixture`, `AIApplicationRecord.fixture`, `SkillRecord.fixture`, `ScanSnapshot.fixture`, `fixtureWithAllRiskLevels`, and `twoItemFixture`. Every helper accepts the parameters used by later tests and supplies stable safe defaults under `/Users/test/Library/SpacePilotFixtures`.

- [ ] **Step 4: Run tests**

Run: `swift test --filter ModelAggregationTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Models Sources/SpacePilotCore/Support Tests/SpacePilotCoreTests/ModelAggregationTests.swift
git commit -m "feat: define storage and AI asset models"
```

---

### Task 3: Protected Paths and Cleanup Planning

**Files:**
- Create: `Sources/SpacePilotCore/Cleanup/PathSafetyPolicy.swift`
- Create: `Sources/SpacePilotCore/Cleanup/CleanupPlanner.swift`
- Create: `Tests/SpacePilotCoreTests/PathSafetyPolicyTests.swift`
- Create: `Tests/SpacePilotCoreTests/CleanupPlannerTests.swift`

**Interfaces:**
- Consumes: `ScannedItem`, `RiskLevel`, `CleanupCandidate`, `CleanupPlan`.
- Produces: `PathSafetyPolicy.validate(_:)`, `CleanupPlanner.makePlan(items:selection:)`.

- [ ] **Step 1: Write protected-path tests**

```swift
func testRejectsBroadAndSystemPaths() {
    let policy = PathSafetyPolicy(homeDirectory: URL(fileURLWithPath: "/Users/test"))
    for path in ["/", "/System", "/Library", "/Users/test", "/Applications"] {
        XCTAssertThrowsError(try policy.validate(URL(fileURLWithPath: path)))
    }
}

func testAllowsDescendantCacheFile() throws {
    let policy = PathSafetyPolicy(homeDirectory: URL(fileURLWithPath: "/Users/test"))
    XCTAssertNoThrow(try policy.validate(URL(fileURLWithPath: "/Users/test/Library/Caches/app/file")))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter PathSafetyPolicyTests`

Expected: FAIL because `PathSafetyPolicy` is missing.

- [ ] **Step 3: Implement canonical path validation**

`validate(_:)` standardizes and resolves symlinks, rejects empty paths, filesystem roots, the home root, `/System`, `/Library`, `/Applications`, `/Users`, `/Volumes`, and any target outside the configured internal volume. It returns the canonical URL when safe.

`CleanupPlanner` rejects `.managed` items, rejects sensitive items unless their IDs are in `separatelyConfirmedSensitiveIDs`, and records expected file resource identifier, size, and modification date in each candidate.

- [ ] **Step 4: Test plan behavior**

```swift
func testSensitiveItemRequiresSeparateConfirmation() {
    let planner = CleanupPlanner(policy: .fixture)
    XCTAssertThrowsError(try planner.makePlan(
        items: [.fixture(path: "/Users/test/Library/AI/conversation.json", risk: .sensitive)],
        selectedIDs: [.fixtureID],
        separatelyConfirmedSensitiveIDs: []
    ))
}
```

Run: `swift test --filter CleanupPlannerTests`

Expected: PASS after implementation.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Cleanup Tests/SpacePilotCoreTests/PathSafetyPolicyTests.swift Tests/SpacePilotCoreTests/CleanupPlannerTests.swift
git commit -m "feat: add protected cleanup planning"
```

---

### Task 4: Filesystem Traversal and Internal Volume Scan

**Files:**
- Create: `Sources/SpacePilotCore/Scanning/FileSystemAccess.swift`
- Create: `Sources/SpacePilotCore/Scanning/DirectoryScanner.swift`
- Create: `Sources/SpacePilotCore/Scanning/VolumeScanner.swift`
- Create: `Sources/SpacePilotCore/Models/ScanCoverage.swift`
- Create: `Tests/SpacePilotCoreTests/DirectoryScannerTests.swift`
- Create: `Tests/SpacePilotCoreTests/VolumeScannerTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/TemporaryTree.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/FixtureFileSystemAccess.swift`

**Interfaces:**
- Produces: `DirectoryScanning.scan(root:options:) async throws -> DirectoryScanResult`, `VolumeScanning.scan() async throws -> VolumeRecord`.
- Consumes: `ScannedItem`, `ItemCategory`, `ScanCoverage`.

- [ ] **Step 1: Write fixture traversal tests**

```swift
func testScannerUsesAllocatedSizeAndRecordsUnreadablePaths() async throws {
    let fixture = try TemporaryTree(files: ["a.bin": 100, "nested/b.bin": 200])
    let access = FixtureFileSystemAccess(unreadable: [fixture.url.appending(path: "nested")])
    let result = try await DirectoryScanner(access: access).scan(root: fixture.url, options: .init())
    XCTAssertEqual(result.items.map(\.allocatedSize).reduce(0, +), 100)
    XCTAssertEqual(result.coverage.deniedPaths.count, 1)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter DirectoryScannerTests`

Expected: FAIL with missing scanner symbols.

- [ ] **Step 3: Implement cancellable traversal**

Use `FileManager.DirectoryEnumerator` with resource keys for allocated size, regular-file status, directory status, dates, volume identifier, and file resource identifier. Call `Task.checkCancellation()` every 128 entries. Do not follow package descendants by default. Record denied paths without failing the entire scan.

`TemporaryTree` creates one `FileManager.default.temporaryDirectory.appending(path: "SpacePilotTests-\(UUID().uuidString)")` root, writes exact byte counts, and removes only that validated root in `deinit`. `FixtureFileSystemAccess` conforms to `FileSystemAccess` and throws a controlled permission error for the configured unreadable URLs.

`VolumeScanner` reads capacity, available capacity for important usage, and volume identity from `/`, and rejects non-internal volume roots for first-version scan requests.

- [ ] **Step 4: Run focused and full tests**

Run: `swift test --filter DirectoryScannerTests && swift test --filter VolumeScannerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Scanning Sources/SpacePilotCore/Models/ScanCoverage.swift Tests/SpacePilotCoreTests
git commit -m "feat: scan internal storage with coverage reporting"
```

---

### Task 5: Application Inventory and Artifact Associations

**Files:**
- Create: `Sources/SpacePilotCore/Applications/ApplicationScanner.swift`
- Create: `Sources/SpacePilotCore/Applications/ApplicationArtifactResolver.swift`
- Create: `Sources/SpacePilotCore/Applications/ApplicationRule.swift`
- Create: `Tests/SpacePilotCoreTests/ApplicationScannerTests.swift`
- Create: `Tests/SpacePilotCoreTests/ApplicationArtifactResolverTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/TestAppBuilder.swift`

**Interfaces:**
- Produces: `ApplicationScanning.scan(locations:)`, `ApplicationArtifactResolving.resolve(application:homeDirectory:)`.
- Consumes: `ApplicationRecord`, `ArtifactAssociation`, `DirectoryScanning`.

- [ ] **Step 1: Write bundle metadata test**

```swift
func testReadsBundleIdentifierVersionAndExecutableSize() async throws {
    let appURL = try TestAppBuilder.make(
        name: "Example", bundleID: "com.example.Example", version: "2.1", executableBytes: 512
    )
    let records = try await ApplicationScanner().scan(locations: [appURL.deletingLastPathComponent()])
    XCTAssertEqual(records.first?.bundleIdentifier, "com.example.Example")
    XCTAssertEqual(records.first?.version, "2.1")
    XCTAssertGreaterThanOrEqual(records.first?.allocatedSize ?? 0, 512)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter ApplicationScannerTests`

Expected: FAIL with missing scanner.

- [ ] **Step 3: Implement inventory and evidence-based resolver**

Scan `/Applications`, `/System/Applications`, and `~/Applications`, deduplicate by standardized bundle URL, and never descend into application packages as ordinary directories.

Resolver evidence weights:

```swift
public enum AssociationEvidence: String, Codable, Sendable {
    case exactBundleIdentifier, exactContainerIdentifier, knownRule
    case signedHelperRelationship, vendorAndNameMatch
}

public enum AssociationConfidence: Int, Codable, Comparable, Sendable {
    case low = 20, medium = 60, high = 90
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
```

Search only known roots such as `~/Library/Application Support`, `Caches`, `Preferences`, `Logs`, `Saved Application State`, `Containers`, and `Group Containers`. Exact bundle-ID matches are high confidence; vendor/name-only matches are medium and never preselected.

- [ ] **Step 4: Test user-document exclusion**

Add a fixture where `~/Documents/Example Project` matches the app name. Assert that it is absent from resolver candidates.

Run: `swift test --filter ApplicationArtifactResolverTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Applications Tests/SpacePilotCoreTests
git commit -m "feat: inventory apps and explain related files"
```

---

### Task 6: Codex, Claude, and Basic AI Footprint Adapters

**Files:**
- Create: `Sources/SpacePilotCore/AI/AIApplicationAdapter.swift`
- Create: `Sources/SpacePilotCore/AI/RuleBasedAIAdapter.swift`
- Create: `Sources/SpacePilotCore/AI/CodexAdapter.swift`
- Create: `Sources/SpacePilotCore/AI/ClaudeAdapter.swift`
- Create: `Sources/SpacePilotCore/AI/BasicAIApplicationScanner.swift`
- Create: `Tests/SpacePilotCoreTests/AIAdapterTests.swift`

**Interfaces:**
- Produces: `AIApplicationAdapting.scan(homeDirectory:)`, `AIAssetRule`.
- Consumes: `AIApplicationRecord`, `ScannedItem`, `DirectoryScanning`.

- [ ] **Step 1: Write metadata-only classification tests**

```swift
func testCodexClassifiesKnownAssetsWithoutReadingContents() async throws {
    let tree = try TemporaryTree(files: [
        ".codex/sessions/session.jsonl": 120,
        ".codex/logs/codex.log": 80,
        ".codex/cache/index.bin": 200,
        ".codex/config.toml": 20
    ])
    let result = try await CodexAdapter().scan(homeDirectory: tree.url)
    XCTAssertEqual(result.itemsByCategory[.conversation]?.count, 1)
    XCTAssertEqual(result.itemsByCategory[.log]?.count, 1)
    XCTAssertEqual(result.itemsByCategory[.cache]?.count, 1)
    XCTAssertEqual(result.itemsByCategory[.aiData]?.count, 1)
    XCTAssertTrue(result.indexedContentBodies.isEmpty)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter AIAdapterTests`

Expected: FAIL with missing adapters.

- [ ] **Step 3: Implement rule-driven adapters**

`AIAssetRule` contains relative path pattern, category, risk, and regeneration explanation. Codex recognizes `.codex`; Claude recognizes `.claude`. Classify by relative path and filename only. Basic AI reporting detects known app bundles and configured roots for ChatGPT, Ollama, and OpenCode, returning only total size and recognized root list.

Reuse `TemporaryTree` from Task 4; the helper exposes only its root URL and never reads created file contents after writing them.

- [ ] **Step 4: Test unknown assets remain unclassified**

Add `~/.codex/mystery/private.dat`; assert category `.unclassified`, risk `.sensitive`, and no cleanup recommendation.

Run: `swift test --filter AIAdapterTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/AI Tests/SpacePilotCoreTests/AIAdapterTests.swift
git commit -m "feat: analyze Codex and Claude local footprints"
```

---

### Task 7: Skill Scope, Metadata, and Conflict Indexing

**Files:**
- Create: `Sources/SpacePilotCore/Skills/SkillScanner.swift`
- Create: `Sources/SpacePilotCore/Skills/SkillManifestParser.swift`
- Create: `Sources/SpacePilotCore/Skills/SkillConflictDetector.swift`
- Create: `Sources/SpacePilotCore/Support/ContentFingerprint.swift`
- Create: `Tests/SpacePilotCoreTests/SkillScannerTests.swift`
- Create: `Tests/SpacePilotCoreTests/SkillConflictDetectorTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/SkillFixtureRoots.swift`

**Interfaces:**
- Produces: `SkillScanning.scan(roots:)`, `SkillRoot`, `SkillConflictDetector.detect(in:)`.
- Consumes: `SkillRecord`, `SkillScope`.

- [ ] **Step 1: Write real-scope fixture tests**

```swift
func testPreservesSharedCodexAndClaudeScopes() async throws {
    let roots = try SkillFixtureRoots.make(shared: ["lark-doc"], codex: ["imagegen"], claude: ["smart-debug"])
    let records = try await SkillScanner().scan(roots: roots.skillRoots)
    XCTAssertEqual(records.first(named: "lark-doc")?.scope, .sharedAgents)
    XCTAssertEqual(records.first(named: "imagegen")?.scope, .agentSpecific(agent: "Codex"))
    XCTAssertEqual(records.first(named: "smart-debug")?.scope, .agentSpecific(agent: "Claude"))
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter SkillScannerTests`

Expected: FAIL with missing scanner.

- [ ] **Step 3: Implement parser and scanner**

Parse YAML-like front matter only for `name` and `description`; do not execute scripts or resolve remote resources. Hash `SKILL.md` plus relative file names with CryptoKit SHA-256. Production roots are:

```swift
[
    SkillRoot(url: home.appending(path: ".agents/skills"), scope: .sharedAgents),
    SkillRoot(url: home.appending(path: ".codex/skills"), scope: .agentSpecific(agent: "Codex")),
    SkillRoot(url: home.appending(path: ".claude/skills"), scope: .agentSpecific(agent: "Claude"))
]
```

Plugin and system roots are supplied separately with `.pluginProvided` and `.systemManaged` scopes. No method moves a Skill between roots.

`SkillFixtureRoots.make(shared:codex:claude:)` builds `SKILL.md` files under a `TemporaryTree` and returns `[SkillRoot]`. Add `Collection where Element == SkillRecord` test helper `first(named:)` in the same fixture file.

- [ ] **Step 4: Detect duplicates and same-name conflicts**

Test identical fingerprints as duplicates and same names with different fingerprints as conflicts. Assert shared plus agent-specific same-name records produce an override warning for that agent.

Run: `swift test --filter SkillConflictDetectorTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Skills Sources/SpacePilotCore/Support/ContentFingerprint.swift Tests/SpacePilotCoreTests
git commit -m "feat: index Skill scopes and conflicts"
```

---

### Task 8: Plugin Manifest and Parent-Child Indexing

**Files:**
- Create: `Sources/SpacePilotCore/Plugins/PluginScanner.swift`
- Create: `Sources/SpacePilotCore/Plugins/PluginManifest.swift`
- Create: `Sources/SpacePilotCore/Plugins/PluginCapability.swift`
- Create: `Tests/SpacePilotCoreTests/PluginScannerTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/PluginFixture.swift`

**Interfaces:**
- Produces: `PluginScanning.scan(roots:)`, `PluginRecord`, parent-managed `SkillRecord` values.
- Consumes: `SkillScanning`, `DirectoryScanning`.

- [ ] **Step 1: Write plugin fixture test**

```swift
func testPluginOwnsBundledSkills() async throws {
    let plugin = try PluginFixture.make(
        name: "product-design", version: "0.1.52", skillNames: ["index", "audit"]
    )
    let result = try await PluginScanner(skillScanner: SkillScanner()).scan(roots: [plugin.root])
    XCTAssertEqual(result.plugins.first?.version, "0.1.52")
    XCTAssertEqual(result.skills.count, 2)
    XCTAssertTrue(result.skills.allSatisfy { $0.managementStatus == .parentManaged })
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter PluginScannerTests`

Expected: FAIL with missing plugin types.

- [ ] **Step 3: Implement safe manifest reading**

Read `.codex-plugin/plugin.json` and package metadata as untrusted JSON. Record name, version, source root, allocated size, and discovered component paths. Reject paths escaping the Plugin root. Treat bundled Skills as `.pluginProvided(pluginID:)` and `.parentManaged`. Expose management capability as `.officialHandoff` unless a supported owner adapter explicitly provides more.

`PluginFixture.make(name:version:skillNames:)` writes a valid manifest and one minimal `SKILL.md` per requested Skill under a validated `TemporaryTree`, then returns both the package root and the retained tree owner.

- [ ] **Step 4: Test traversal rejection and managed cleanup exclusion**

Add a manifest path containing `../../`; assert it is ignored and a diagnostic is recorded. Pass a bundled Skill to `CleanupPlanner`; assert rejection.

Run: `swift test --filter PluginScannerTests --filter CleanupPlannerTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Plugins Tests/SpacePilotCoreTests/PluginScannerTests.swift
git commit -m "feat: map Plugins to managed Skills"
```

---

### Task 9: SQLite Snapshot and History Persistence

**Files:**
- Create: `Sources/SpacePilotCore/Persistence/SQLiteConnection.swift`
- Create: `Sources/SpacePilotCore/Persistence/SQLiteIndexStore.swift`
- Create: `Sources/SpacePilotCore/Persistence/IndexSchema.swift`
- Create: `Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift`

**Interfaces:**
- Produces: `SnapshotStoring.save(snapshot:)`, `latestSnapshot()`, `save(transaction:)`, `cleanupHistory()`.
- Consumes: `ScanSnapshot`, `CleanupTransaction`.

- [ ] **Step 1: Write persistence round-trip tests**

```swift
func testLatestCompleteSnapshotReplacesOlderSnapshotAtomically() async throws {
    let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
    try await store.save(snapshot: .fixture(id: UUID(), completedAt: .distantPast))
    let latest = ScanSnapshot.fixture(id: UUID(), completedAt: .now)
    try await store.save(snapshot: latest)
    XCTAssertEqual(try await store.latestSnapshot()?.id, latest.id)
}

func testIncompleteSessionNeverBecomesLatest() async throws {
    let store = try SQLiteIndexStore(url: temporaryDatabaseURL())
    try await store.begin(sessionID: UUID())
    XCTAssertNil(try await store.latestSnapshot())
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter SQLiteIndexStoreTests`

Expected: FAIL with missing persistence types.

- [ ] **Step 3: Implement serialized SQLite actor**

Use `sqlite3_open_v2`, prepared statements, bound parameters, WAL mode, foreign keys, and transactions. Store model payloads as versioned JSON blobs plus indexed summary columns for timestamp, allocated size, and status. A complete snapshot transaction writes all rows and updates `latest_complete_snapshot` only at commit.

- [ ] **Step 4: Test recovery behavior**

Create an invalid database file, open the store, assert it is moved to a `.corrupt-<timestamp>` sibling and a fresh schema is created without touching filesystem data.

Run: `swift test --filter SQLiteIndexStoreTests`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Persistence Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift
git commit -m "feat: persist scan snapshots and cleanup history"
```

---

### Task 10: Scan Coordinator, Permissions, and App Model

**Files:**
- Create: `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift`
- Create: `Sources/SpacePilotCore/Scanning/ScanProgress.swift`
- Create: `Sources/SpacePilotCore/Permissions/PermissionService.swift`
- Modify: `Sources/SpacePilot/App/AppModel.swift`
- Create: `Tests/SpacePilotCoreTests/ScanCoordinatorTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/ScanningTestDoubles.swift`

**Interfaces:**
- Produces: `ScanCoordinating.scan() -> AsyncStream<ScanEvent>`, `PermissionService.coverageStatus()`.
- Consumes: all scanners and `SnapshotStoring`.

- [ ] **Step 1: Write staged event and cancellation tests**

```swift
func testQuickInventoryArrivesBeforeTargetedCompletion() async throws {
    let coordinator = ScanCoordinator.fixture()
    var stages: [ScanStage] = []
    for try await event in coordinator.scan() {
        stages.append(event.stage)
    }
    XCTAssertEqual(stages.first, .quickInventory)
    XCTAssertEqual(stages.last, .completed)
}

func testCancelledScanDoesNotReplaceLatestSnapshot() async throws {
    let store = InMemorySnapshotStore(latest: .fixture())
    let coordinator = ScanCoordinator.fixture(store: store, suspendDuring: .targetedAnalysis)
    let task = Task { try await coordinator.collectScan() }
    task.cancel()
    _ = try? await task.value
    XCTAssertEqual(await store.saveCount, 0)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter ScanCoordinatorTests`

Expected: FAIL with missing coordinator.

- [ ] **Step 3: Implement staged coordination**

Run volume and application quick inventory first. Run Codex, Claude, Plugin, Skill, application association, and developer-cache work in a bounded task group with at most four active analyzers. Emit progress events on a stream. Save only a completed immutable snapshot.

`PermissionService` reports `.full`, `.limited(deniedPaths:)`, or `.unknown`; it never claims Full Disk Access from a private API. It opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles` on user action.

`ScanningTestDoubles.swift` defines `InMemorySnapshotStore`, deterministic immediate scanners, a suspending scanner that checks cancellation, and `ScanCoordinator.fixture(store:suspendDuring:)`. The store is an actor exposing `saveCount` and `latest` for assertions.

- [ ] **Step 4: Connect AppModel**

`AppModel` is `@MainActor @Observable`, owns scan task, latest snapshot, progress, error banner, selection, and cancellation. It never calls `FileManager` directly.

Run: `swift test --filter ScanCoordinatorTests && swift build`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Scanning Sources/SpacePilotCore/Permissions Sources/SpacePilot/App/AppModel.swift Tests/SpacePilotCoreTests/ScanCoordinatorTests.swift
git commit -m "feat: coordinate progressive local scans"
```

---

### Task 11: Simple Native Feature Interface

**Files:**
- Modify: `Sources/SpacePilot/Views/AppRootView.swift`
- Create: `Sources/SpacePilot/Views/SidebarView.swift`
- Create: `Sources/SpacePilot/Views/Overview/OverviewView.swift`
- Create: `Sources/SpacePilot/Views/Storage/StorageView.swift`
- Create: `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`
- Create: `Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift`
- Create: `Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift`
- Create: `Sources/SpacePilot/Views/History/CleanupHistoryView.swift`
- Create: `Sources/SpacePilot/Views/Shared/ScanStatusView.swift`
- Create: `Sources/SpacePilot/Views/Shared/InspectorDetailView.swift`
- Create: `Sources/SpacePilot/Views/Settings/SettingsView.swift`
- Create: `Sources/SpacePilotCore/Models/AIApplicationTab.swift`
- Create: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Create: `Tests/SpacePilotCoreTests/ViewProjectionTests.swift`

**Interfaces:**
- Consumes: `AppModel`, snapshots, applications, AI apps, Plugins, Skills, cleanup history.
- Produces: complete navigable UI with no filesystem mutation.

- [ ] **Step 1: Test view projections outside SwiftUI**

```swift
func testAIApplicationTabsRemainNestedUnderSelectedApplication() {
    XCTAssertEqual(AIApplicationTab.allCases.map(\.title), [
        "Overview", "Data & Storage", "Plugins", "Skills"
    ])
}

func testOverviewRecommendationsExcludeSensitiveAndManagedByDefault() {
    let projection = OverviewProjection(snapshot: .fixtureWithAllRiskLevels)
    XCTAssertTrue(projection.preselectedRecommendations.allSatisfy { $0.risk == .safe })
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter ViewProjectionTests`

Expected: FAIL because projection types are missing.

- [ ] **Step 3: Implement the native layout**

Use `NavigationSplitView` with a native `.sidebar` list. The detail area uses one dominant list, table, or outline per destination. The toolbar contains scan/cancel and search actions. Use semantic foreground styles, system materials, blue tint, and no hardcoded white backgrounds.

`DeveloperAIView` lists AI applications in its own column. `AIApplicationDetailView` uses a compact picker or tab bar for Overview, Data & Storage, Plugins, and Skills. Plugin and Skill rows show source and management status; they are never top-level sidebar items.

- [ ] **Step 4: Add desktop affordances and accessibility**

Add Command-R to rescan, Escape to cancel, Command-F to focus search, context menus for Reveal in Finder, and accessibility labels that include item name, formatted size, risk, and source. Use `Table` for dense results and plain aligned sections for summaries; use cards only for interactive recommendation groups.

Run: `swift test --filter ViewProjectionTests && swift build`

Expected: PASS with no Swift concurrency warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilot/Views Tests/SpacePilotCoreTests/ViewProjectionTests.swift
git commit -m "feat: add restrained native SpacePilot interface"
```

---

### Task 12: Trash Execution, History, and Verification

**Files:**
- Create: `Sources/SpacePilotCore/Cleanup/TrashMoving.swift`
- Create: `Sources/SpacePilotCore/Cleanup/CleanupExecutor.swift`
- Create: `Sources/SpacePilotCore/Cleanup/CleanupVerifier.swift`
- Create: `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`
- Modify: `Sources/SpacePilot/App/AppModel.swift`
- Modify: `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`
- Modify: `Sources/SpacePilot/Views/Storage/StorageView.swift`
- Create: `Tests/SpacePilotCoreTests/CleanupExecutorTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/RecordingTrashMover.swift`

**Interfaces:**
- Produces: `CleanupExecuting.execute(plan:)`, `CleanupVerifier.verify(transaction:)`.
- Consumes: immutable `CleanupPlan`, `PathSafetyPolicy`, `SnapshotStoring`.

- [ ] **Step 1: Write identity revalidation and partial failure tests**

```swift
func testChangedFileIsSkippedBeforeTrashMove() async throws {
    let mover = RecordingTrashMover()
    let executor = CleanupExecutor(policy: .fixture, mover: mover)
    let plan = CleanupPlan.fixture(expectedModificationDate: .distantPast)
    let result = try await executor.execute(plan: plan)
    XCTAssertEqual(result.outcomes.first?.status, .skippedChanged)
    XCTAssertTrue(mover.movedURLs.isEmpty)
}

func testFailureIsNotReportedAsTotalSuccess() async throws {
    let mover = RecordingTrashMover(failingAtIndex: 1)
    let result = try await CleanupExecutor(policy: .fixture, mover: mover).execute(plan: .twoItemFixture)
    XCTAssertEqual(result.summary, .partialFailure)
}
```

- [ ] **Step 2: Run and verify failure**

Run: `swift test --filter CleanupExecutorTests`

Expected: FAIL with missing executor.

- [ ] **Step 3: Implement execution and verification**

Production `FileManagerTrashMover` calls `FileManager.trashItem(at:resultingItemURL:)`. Before every move, revalidate canonical path, resource identifier, size, and modification date. Stop dependent candidates after failure; preserve independent outcomes. Save the transaction, then run a targeted rescan and record verified freed bytes.

`RecordingTrashMover` records URLs without touching disk and can throw at one configured move index. Cleanup tests use only paths inside a `TemporaryTree`; `PathSafetyPolicy.fixture` is configured with that tree as both home and allowed volume root.

- [ ] **Step 4: Wire explicit confirmation UI**

`CleanupConfirmationView` lists exact paths, formatted sizes, risk, effect, and recovery. Sensitive items require a separate toggle and cannot share the primary one-click selection. Applications must be quit before plan execution. AppModel presents completion as success, partial failure, or failed with per-item details.

Run: `swift test --filter CleanupExecutorTests && swift test`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Cleanup Sources/SpacePilot/App Sources/SpacePilot/Views Tests/SpacePilotCoreTests/CleanupExecutorTests.swift
git commit -m "feat: execute verified reversible cleanup"
```

---

### Task 13: Acceptance Fixtures, Performance, and Release Readiness

**Files:**
- Create: `Tests/SpacePilotCoreTests/AcceptanceTests.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/AcceptanceFixture.swift`
- Create: `script/test_release.sh`
- Create: `README.md`
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Consumes: the complete app and core library.
- Produces: repeatable acceptance evidence and user-facing run instructions.

- [ ] **Step 1: Build the complete acceptance fixture**

The fixture contains:

- Two test applications with exact and medium-confidence related files
- A user document that shares an application name but must never be selected
- Codex and Claude conversations, logs, caches, configs, Plugins, and Skills
- Shared, Codex-specific, Claude-specific, Plugin-provided, and system-managed Skills
- Duplicate and conflicting Skill names
- A changed-after-plan file, a disappearing file, and a simulated unreadable directory

- [ ] **Step 2: Write end-to-end assertions**

```swift
func testAcceptanceFixtureMeetsSafetyAndRelationshipRequirements() async throws {
    let fixture = try AcceptanceFixture.make()
    let snapshot = try await fixture.coordinator.collectScan()
    XCTAssertTrue(snapshot.applications.contains(where: { $0.bundleIdentifier == "com.example.One" }))
    XCTAssertEqual(snapshot.aiApplications.first(named: "Codex")?.tabs, AIApplicationTab.allCases)
    XCTAssertFalse(snapshot.preselectedCleanupItems.contains(where: { $0.url == fixture.userDocument }))
    XCTAssertTrue(snapshot.skills.contains(where: { $0.scope == .sharedAgents }))
    XCTAssertTrue(snapshot.skills.contains(where: { $0.managementStatus == .parentManaged }))
    XCTAssertEqual(snapshot.uniqueAIAllocatedSize, fixture.expectedUniqueAIBytes)
}
```

- [ ] **Step 3: Run all automated checks**

Create `script/test_release.sh` to run:

```bash
swift test --parallel
swift build -c release
./script/build_and_run.sh --verify
/usr/bin/codesign --verify --deep --strict dist/SpacePilot.app
/usr/sbin/spctl --assess --type execute --verbose dist/SpacePilot.app || true
```

The Gatekeeper assessment may report unsigned local development identity; the script must distinguish that expected development state from build or bundle failure.

Run: `./script/test_release.sh`

Expected: all tests PASS, Release build succeeds, app process verification succeeds, code structure verification succeeds.

- [ ] **Step 4: Perform manual interface and safety pass**

Verify on the real Mac:

- Main window opens in front and respects the 1,000 x 680 minimum.
- Light and Dark mode remain legible.
- Keyboard navigation, search, rescan, cancel, and context menus work.
- Without Full Disk Access, coverage is labeled limited.
- No cleanup runs before a confirmation sheet.
- Codex and Claude show nested Data & Storage, Plugins, and Skills tabs.
- Skill sources match `.agents/skills`, `.codex/skills`, `.claude/skills`, Plugin, and system roots.
- No Skill movement action exists.

- [ ] **Step 5: Document and commit**

README includes product scope, privacy model, requirements, `./script/build_and_run.sh`, `swift test`, current direct-distribution status, and the fact that release Developer ID signing and notarization require the owner's Apple Developer credentials.

```bash
git add Tests script README.md
git commit -m "test: verify SpacePilot acceptance requirements"
```

---

## Completion Gate

Do not claim completion until all of the following are current and inspected:

1. `git status --short` contains no unintended files.
2. `swift test --parallel` passes.
3. `swift build -c release` succeeds.
4. `./script/build_and_run.sh --verify` launches the staged app bundle and verifies the process.
5. Acceptance fixture proves application-document exclusion, AI relationships, Skill scopes, no double-counting, and managed-asset protection.
6. Manual UI inspection confirms the simple native hierarchy in Light and Dark mode.
7. The implementation is checked line-by-line against every acceptance criterion in `docs/superpowers/specs/2026-07-22-spacepilot-design.md`.
