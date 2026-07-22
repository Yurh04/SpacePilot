# SpacePilot Performance, Plugins, and Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every primary page responsive with a 1 GB scan snapshot, display real Codex Plugins and their Skills, and provide English and Simplified Chinese UI that follows the macOS system language.

**Architecture:** Decode both real Codex Plugin manifest shapes, preserve Plugin diagnostics in snapshots, and build one immutable `AppSnapshotProjection` off the main actor whenever the latest snapshot changes. SwiftUI views render only projection data and localized strings; they never scan the full `snapshot.items` collection in `body`.

**Tech Stack:** Swift 6, SwiftUI, Observation, Swift Concurrency, Swift Package Manager resources, String Catalog, XCTest, macOS 15+, Apple Silicon.

## Global Constraints

- Support Apple Silicon only.
- Minimum system version is macOS 15.
- Keep all analysis local; do not read conversation or log contents.
- Plugins and Skills remain nested under their owning AI application.
- Support English and Simplified Chinese, follow macOS system language, and fall back to English.
- Do not add third-party dependencies.
- Do not normalize the SQLite schema or add pagination in this change.
- Never broaden cleanup eligibility for managed Plugins or plugin-provided Skills.

---

## File Structure

- Create `Sources/SpacePilotCore/Models/AppSnapshotProjection.swift`: immutable page-ready projection types and bounded aggregation.
- Create `Sources/SpacePilot/Localization/L10n.swift`: typed localized strings and enum display mappings.
- Create `Sources/SpacePilot/Resources/Localizable.xcstrings`: English and Simplified Chinese translations.
- Modify `Sources/SpacePilotCore/Plugins/PluginManifest.swift`: compatible decoding of `skills` as a string or array.
- Modify `Sources/SpacePilotCore/Plugins/PluginScanner.swift`: expand directory declarations and preserve diagnostics.
- Modify `Sources/SpacePilotCore/Models/ScanSnapshot.swift`: persist optional Plugin diagnostics without breaking old snapshots.
- Modify `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift`: attach Plugin results and diagnostics to Codex.
- Modify `Sources/SpacePilot/App/AppModel.swift`: own one background projection task and publish only the newest result.
- Modify the files under `Sources/SpacePilot/Views/`: consume projections and localized strings only.
- Modify `Package.swift` and `script/build_and_run.sh`: package and stage localization resources.
- Extend `Tests/SpacePilotCoreTests/`: Plugin compatibility, projection correctness, limits, and snapshot compatibility.
- Create `Tests/SpacePilotTests/LocalizationTests.swift`: verify English and Simplified Chinese values from the String Catalog.

---

### Task 1: Decode Real Codex Plugin Manifests

**Files:**
- Modify: `Tests/SpacePilotCoreTests/Fixtures/PluginFixture.swift`
- Modify: `Tests/SpacePilotCoreTests/PluginScannerTests.swift`
- Modify: `Sources/SpacePilotCore/Plugins/PluginManifest.swift`
- Modify: `Sources/SpacePilotCore/Plugins/PluginScanner.swift`

**Interfaces:**
- Consumes: `.codex-plugin/plugin.json` with `skills` encoded as either `"./skills/"` or `["skills/a", "skills/b"]`.
- Produces: `PluginManifest.skills: [String]` and `PluginScanner.scan(roots:)` results whose `PluginRecord.skillIDs` own all discovered child Skills.

- [ ] **Step 1: Extend the fixture to emit either manifest shape**

Replace `PluginFixture.swift` with this complete fixture:

```swift
import Foundation
@testable import SpacePilotCore

enum PluginSkillsEncoding {
    case directory(String)
    case paths([String])
}

final class PluginFixture: @unchecked Sendable {
    let tree: TemporaryTree
    let root: URL

    private init(tree: TemporaryTree, root: URL) {
        self.tree = tree
        self.root = root
    }

    static func make(
        name: String,
        version: String,
        skillNames: [String],
        extraSkillPaths: [String] = [],
        skillsEncoding: PluginSkillsEncoding? = nil
    ) throws -> PluginFixture {
        let tree = try TemporaryTree(files: [:])
        let root = tree.url.appending(path: name, directoryHint: .isDirectory)
        let manifestDirectory = root.appending(path: ".codex-plugin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        let explicitPaths = skillNames.map { "skills/\($0)" } + extraSkillPaths
        let declaration = skillsEncoding ?? .paths(explicitPaths)
        let skillsJSON: Any
        switch declaration {
        case .directory(let path): skillsJSON = path
        case .paths(let paths): skillsJSON = paths
        }
        let manifest: [String: Any] = [
            "name": name,
            "version": version,
            "skills": skillsJSON,
            "dependencies": ["codex"]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: manifestDirectory.appending(path: "plugin.json"))
        for skill in skillNames {
            let folder = root.appending(path: "skills/\(skill)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let content = "---\nname: \(skill)\ndescription: \(skill) from \(name)\n---\nInstructions"
            try Data(content.utf8).write(to: folder.appending(path: "SKILL.md"))
        }
        return PluginFixture(tree: tree, root: root)
    }
}
```

- [ ] **Step 2: Write the failing directory-manifest test**

Add to `PluginScannerTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the test and verify the current decoder rejects the string**

Run:

```bash
swift test --filter PluginScannerTests/testDirectorySkillsDeclarationDiscoversChildSkills
```

Expected: FAIL because `PluginManifest.skills` only decodes `[String]`.

- [ ] **Step 4: Implement compatible manifest decoding**

Replace synthesized decoding in `PluginManifest.swift` with:

```swift
public struct PluginManifest: Decodable, Sendable {
    public let name: String
    public let version: String?
    public let skills: [String]
    public let dependencies: [String]

    private enum CodingKeys: String, CodingKey {
        case name, version, skills, dependencies
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        version = try values.decodeIfPresent(String.self, forKey: .version)
        dependencies = try values.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        if let path = try? values.decode(String.self, forKey: .skills) {
            skills = [path]
        } else {
            skills = try values.decodeIfPresent([String].self, forKey: .skills) ?? []
        }
    }

    public init(name: String, version: String?, skills: [String], dependencies: [String]) {
        self.name = name
        self.version = version
        self.skills = skills
        self.dependencies = dependencies
    }
}
```

- [ ] **Step 5: Expand declared directories without weakening path safety**

In `PluginScanner`, replace direct `acceptedFolders.append(folder)` behavior with:

```swift
private func skillFolders(for relativePath: String, beneath root: URL) -> [URL] {
    guard let candidate = validatedComponent(relativePath, beneath: root) else { return [] }
    let manifest = candidate.appending(path: "SKILL.md")
    if FileManager.default.fileExists(atPath: manifest.path) { return [candidate] }

    guard let children = try? FileManager.default.contentsOfDirectory(
        at: candidate,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return [] }
    return children.filter {
        FileManager.default.fileExists(atPath: $0.appending(path: "SKILL.md").path)
    }
}
```

Call `skillFolders(for:beneath:)` for every declared path. If it returns no folders, append a diagnostic that identifies the rejected or empty declaration. Keep `validatedComponent` unchanged so absolute paths and `..` remain rejected.

- [ ] **Step 6: Run Plugin tests**

Run:

```bash
swift test --filter PluginScannerTests
```

Expected: all Plugin scanner tests PASS, including traversal rejection.

- [ ] **Step 7: Commit the Plugin parser change**

```bash
git add Sources/SpacePilotCore/Plugins/PluginManifest.swift Sources/SpacePilotCore/Plugins/PluginScanner.swift Tests/SpacePilotCoreTests/Fixtures/PluginFixture.swift Tests/SpacePilotCoreTests/PluginScannerTests.swift
git commit -m "fix: discover plugins with directory skill manifests"
```

---

### Task 2: Persist Plugin Diagnostics and Codex Ownership

**Files:**
- Modify: `Sources/SpacePilotCore/Models/ScanSnapshot.swift`
- Modify: `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift`
- Modify: `Tests/SpacePilotCoreTests/AcceptanceTests.swift`
- Modify: `Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift`
- Modify: `Tests/SpacePilotCoreTests/Fixtures/ModelFixtures.swift`

**Interfaces:**
- Consumes: `PluginScanResult.plugins`, `PluginScanResult.skills`, and `PluginScanResult.diagnostics`.
- Produces: `ScanSnapshot.pluginDiagnostics: [String]?`; Codex owns all discovered Plugin IDs; old persisted snapshots decode with `pluginDiagnostics == nil`.

- [ ] **Step 1: Write failing ownership and persistence assertions**

Extend the acceptance test:

```swift
let codex = try XCTUnwrap(snapshot.aiApplications.first { $0.name == "Codex" })
XCTAssertFalse(snapshot.plugins.isEmpty)
XCTAssertEqual(codex.pluginIDs, Set(snapshot.plugins.map(\.id)))
XCTAssertTrue(snapshot.aiApplications.filter { $0.name != "Codex" }.allSatisfy(\.pluginIDs.isEmpty))
XCTAssertNotNil(snapshot.pluginDiagnostics)
```

Add a SQLite round-trip assertion:

```swift
let snapshot = ScanSnapshot.fixture(pluginDiagnostics: ["Invalid manifest"])
try await store.save(snapshot: snapshot)
XCTAssertEqual(try await store.latestSnapshot()?.pluginDiagnostics, ["Invalid manifest"])
```

- [ ] **Step 2: Run focused tests and verify missing API failure**

```bash
swift test --filter AcceptanceTests
swift test --filter SQLiteIndexStoreTests
```

Expected: compilation FAIL because `pluginDiagnostics` does not exist.

- [ ] **Step 3: Add backward-compatible snapshot diagnostics**

Add to `ScanSnapshot`:

```swift
public let pluginDiagnostics: [String]?
```

Add `pluginDiagnostics: [String]? = nil` to its initializer and assign it. Because the stored property is optional, JSON snapshots created before this field existed decode it as `nil`.

Update fixture constructors to accept and forward the same optional parameter.

- [ ] **Step 4: Attach scan diagnostics to completed snapshots**

In `ScanCoordinator`, set:

```swift
pluginDiagnostics: pluginResult.diagnostics
```

when creating the completed `ScanSnapshot`. Keep quick inventory snapshots at `nil`. Continue assigning `Set(pluginResult.plugins.map(\.id))` only to Codex.

- [ ] **Step 5: Run persistence and acceptance tests**

```bash
swift test --filter AcceptanceTests
swift test --filter SQLiteIndexStoreTests
```

Expected: PASS.

- [ ] **Step 6: Commit snapshot Plugin metadata**

```bash
git add Sources/SpacePilotCore/Models/ScanSnapshot.swift Sources/SpacePilotCore/Scanning/ScanCoordinator.swift Tests/SpacePilotCoreTests/AcceptanceTests.swift Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift Tests/SpacePilotCoreTests/Fixtures/ModelFixtures.swift
git commit -m "feat: preserve plugin discovery status"
```

---

### Task 3: Build One Bounded App Snapshot Projection

**Files:**
- Create: `Sources/SpacePilotCore/Models/AppSnapshotProjection.swift`
- Modify: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Modify: `Tests/SpacePilotCoreTests/ViewProjectionTests.swift`

**Interfaces:**
- Consumes: one immutable `ScanSnapshot`.
- Produces: `AppSnapshotProjection(snapshot:)`, containing page-ready Overview, Storage, Applications, and Developer & AI data with stable IDs and bounded lists.

- [ ] **Step 1: Write failing projection API tests**

Add tests using small fixtures:

```swift
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

    let projection = AppSnapshotProjection(snapshot: snapshot)

    XCTAssertEqual(projection.snapshotID, snapshot.id)
    XCTAssertEqual(projection.developerAI.applications.first?.plugins.map(\.name), ["product-design"])
    XCTAssertLessThanOrEqual(projection.storage.largestItems.count, StorageProjection.itemDisplayLimit)
}
```

Add a performance guard based on bounded outputs, not wall-clock timing:

```swift
func testOverviewAndStorageOutputsStayBounded() {
    let items = (0..<500).map { ScannedItem.fixture(allocatedSize: Int64($0)) }
    let snapshot = ScanSnapshot(
        completedAt: .now, volume: nil, items: items, applications: [],
        aiApplications: [], plugins: [], skills: [], coverage: .complete
    )
    let projection = AppSnapshotProjection(snapshot: snapshot)
    XCTAssertEqual(projection.overview.recommendations.count, 8)
    XCTAssertEqual(projection.storage.largestItems.count, 100)
}
```

- [ ] **Step 2: Run tests and verify the projection type is missing**

```bash
swift test --filter ViewProjectionTests
```

Expected: compilation FAIL for missing `AppSnapshotProjection` and `DeveloperAIProjection`.

- [ ] **Step 3: Define page-ready projection types**

Create focused public Sendable value types:

```swift
public struct AppSnapshotProjection: Sendable {
    public let snapshotID: UUID
    public let overview: OverviewProjection
    public let storage: StorageProjection
    public let applications: ApplicationListProjection
    public let developerAI: DeveloperAIProjection

    public init(snapshot: ScanSnapshot) {
        snapshotID = snapshot.id
        overview = OverviewProjection(snapshot: snapshot)
        storage = StorageProjection(snapshot: snapshot)
        applications = ApplicationListProjection(snapshot: snapshot, searchText: "")
        developerAI = DeveloperAIProjection(snapshot: snapshot)
    }
}

public struct AIApplicationProjection: Identifiable, Sendable {
    public var id: UUID { application.id }
    public let application: AIApplicationRecord
    public let totalSize: Int64
    public let dataItems: [ScannedItem]
    public let plugins: [PluginRecord]
    public let skills: [SkillRecord]
}

public struct DeveloperAIProjection: Sendable {
    public let developerBytes: Int64
    public let applications: [AIApplicationProjection]
    public let pluginDiagnostics: [String]
}
```

`DeveloperAIProjection.init(snapshot:)` must build Plugin and Skill dictionaries by ID once, create a reverse lookup from AI item ID to application ID, walk `snapshot.items` once, and sort only the resulting per-AI collections.

- [ ] **Step 4: Bound Overview recommendations**

Change `OverviewProjection` to expose:

```swift
public let recommendations: [ScannedItem]
public static let recommendationDisplayLimit = 8
```

Use the same bounded heap selection pattern already used by Storage, preferring safe items with larger `allocatedSize`. Compute `reclaimableBytes` over all safe items during the scan, but retain only eight rows for display.

- [ ] **Step 5: Keep Application projection search off the full item set**

Store the full sorted application summaries and total-size dictionary in `ApplicationListProjection`. Add:

```swift
public func filtered(by searchText: String) -> [ApplicationRecord] {
    guard !searchText.isEmpty else { return applications }
    return applications.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
}
```

This method may filter applications but must not read `snapshot.items`.

- [ ] **Step 6: Run projection tests**

```bash
swift test --filter ViewProjectionTests
swift test --filter ModelAggregationTests
```

Expected: PASS with bounded counts and correct Plugin/Skill totals.

- [ ] **Step 7: Commit the projection layer**

```bash
git add Sources/SpacePilotCore/Models/AppSnapshotProjection.swift Sources/SpacePilotCore/Models/ViewProjections.swift Tests/SpacePilotCoreTests/ViewProjectionTests.swift
git commit -m "perf: build bounded page projections"
```

---

### Task 4: Publish Projections Off the Main Actor

**Files:**
- Modify: `Sources/SpacePilot/App/AppModel.swift`
- Modify: `Sources/SpacePilot/Views/AppRootView.swift`
- Modify: `Sources/SpacePilot/Views/Overview/OverviewView.swift`
- Modify: `Sources/SpacePilot/Views/Storage/StorageView.swift`
- Modify: `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift`

**Interfaces:**
- Consumes: `AppSnapshotProjection(snapshot:)` from Task 3.
- Produces: `AppModel.projection: AppSnapshotProjection?` and views that show an immediate preparation state while projection work runs in a detached task.

- [ ] **Step 1: Replace page-specific projection state with one property**

In `AppModel` define:

```swift
var projection: AppSnapshotProjection?
private var projectionTask: Task<Void, Never>?

private func apply(snapshot: ScanSnapshot) {
    latestSnapshot = snapshot
    projection = nil
    projectionTask?.cancel()
    projectionTask = Task {
        let result = await Task.detached(priority: .userInitiated) {
            AppSnapshotProjection(snapshot: snapshot)
        }.value
        guard !Task.isCancelled, latestSnapshot?.id == result.snapshotID else { return }
        projection = result
    }
}
```

Use `apply(snapshot:)` for both saved-state loading and scan events. Remove `storageProjection` and `storageProjectionTask`.

- [ ] **Step 2: Pass projection slices from AppRootView**

Use the following data flow:

```swift
OverviewView(projection: model.projection?.overview, hasSnapshot: model.latestSnapshot != nil, ...)
StorageView(projection: model.projection?.storage, hasSnapshot: model.latestSnapshot != nil, ...)
ApplicationsView(projection: model.projection?.applications, hasSnapshot: model.latestSnapshot != nil, ...)
DeveloperAIView(model: model, projection: model.projection?.developerAI, hasSnapshot: model.latestSnapshot != nil)
```

- [ ] **Step 3: Remove full-snapshot work from all view bodies**

Delete these patterns from UI files:

```swift
OverviewProjection(snapshot: snapshot)
StorageProjection(snapshot: snapshot)
ApplicationListProjection(snapshot: snapshot, searchText: searchText)
snapshot.items.filter { ... }
snapshot.items.first { ... }
snapshot.plugins.filter { ... }
snapshot.skills.filter { ... }
```

Views may filter only bounded projection arrays or the small application list. `AIApplicationDetailView` must accept one `AIApplicationProjection`, not the full snapshot.

- [ ] **Step 4: Add explicit preparation states**

Each primary data page follows:

```swift
if let projection {
    pageContent(projection)
} else if hasSnapshot {
    ProgressView("Preparing summary…")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
} else {
    emptyState
}
```

Use temporary English constants until Task 6 introduces `L10n`; do not add new full-snapshot computations.

- [ ] **Step 5: Build and search for forbidden full-item reads**

```bash
swift build
rg -n "snapshot\.items\.(filter|sorted|first)|Projection\(snapshot:" Sources/SpacePilot/Views
```

Expected: build PASS; search returns no matches.

- [ ] **Step 6: Commit background projection wiring**

```bash
git add Sources/SpacePilot/App/AppModel.swift Sources/SpacePilot/Views/AppRootView.swift Sources/SpacePilot/Views/Overview/OverviewView.swift Sources/SpacePilot/Views/Storage/StorageView.swift Sources/SpacePilot/Views/Applications/ApplicationsView.swift Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift
git commit -m "perf: keep full snapshots out of SwiftUI rendering"
```

---

### Task 5: Make Plugins Visible and Explain Empty States

**Files:**
- Modify: `Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift`
- Modify: `Sources/SpacePilotCore/Models/PluginRecord.swift`
- Modify: `Tests/SpacePilotCoreTests/ViewProjectionTests.swift`

**Interfaces:**
- Consumes: `AIApplicationProjection.plugins`, `.skills`, and `DeveloperAIProjection.pluginDiagnostics`.
- Produces: Codex Plugin table rows containing name, version, source, allocated size, Skill count, and management status; distinct empty and diagnostic states.

- [ ] **Step 1: Add a failing Plugin projection assertion**

Add:

```swift
func testAIApplicationProjectionExposesPluginSkillCount() throws {
    let skillID = UUID()
    let plugin = PluginRecord(
        name: "product-design", version: "1", url: URL(fileURLWithPath: "/tmp/plugin"),
        source: "openai-curated-remote", allocatedSize: 42,
        skillIDs: [skillID], dependencies: []
    )
    XCTAssertEqual(plugin.skillCount, 1)
}
```

- [ ] **Step 2: Run the test and verify missing API failure**

```bash
swift test --filter ViewProjectionTests/testAIApplicationProjectionExposesPluginSkillCount
```

Expected: compilation FAIL for missing `skillCount`.

- [ ] **Step 3: Add the display-safe count**

In `PluginRecord`:

```swift
public var skillCount: Int { skillIDs.count }
```

- [ ] **Step 4: Render the Plugin table and empty states**

The Plugin tab must use these columns:

```swift
TableColumn("Plugin") { plugin in
    VStack(alignment: .leading) {
        Text(plugin.name)
        Text(plugin.source).font(.caption).foregroundStyle(.secondary)
    }
}
TableColumn("Version") { Text($0.version ?? "—") }
TableColumn("Skills") { Text($0.skillCount.formatted()) }
TableColumn("Management") { _ in Text("Official handoff") }
TableColumn("Space") { Text(ByteCount.string($0.allocatedSize)) }
```

When `plugins.isEmpty`:

- diagnostics empty: show `ContentUnavailableView("No Plugins installed", systemImage: "puzzlepiece.extension")`.
- diagnostics non-empty: show `ContentUnavailableView("Plugin discovery failed", systemImage: "exclamationmark.triangle")` followed by sanitized diagnostic summaries.

Only Codex receives Plugin diagnostics. Other AI applications show their normal no-Plugins state.

- [ ] **Step 5: Run tests and build**

```bash
swift test --filter ViewProjectionTests
swift build
```

Expected: PASS.

- [ ] **Step 6: Commit Plugin presentation**

```bash
git add Sources/SpacePilotCore/Models/PluginRecord.swift Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift Tests/SpacePilotCoreTests/ViewProjectionTests.swift
git commit -m "feat: show codex plugins and discovery status"
```

---

### Task 6: Add System-Language Localization Infrastructure

**Files:**
- Modify: `Package.swift`
- Create: `Sources/SpacePilot/Localization/L10n.swift`
- Create: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Create: `Tests/SpacePilotTests/LocalizationTests.swift`
- Modify: `script/build_and_run.sh`

**Interfaces:**
- Consumes: macOS preferred language and SwiftPM resource bundle.
- Produces: typed `L10n` strings resolved from English and `zh-Hans`; staged `.app` contains the SwiftPM localization resource bundle.

- [ ] **Step 1: Add the app test target and resources**

Update `Package.swift`:

```swift
defaultLocalization: "en",
```

and configure targets:

```swift
.executableTarget(
    name: "SpacePilot",
    dependencies: ["SpacePilotCore"],
    resources: [.process("Resources")]
),
.testTarget(
    name: "SpacePilotTests",
    dependencies: ["SpacePilot"]
)
```

- [ ] **Step 2: Write failing localization tests**

Create:

```swift
import XCTest
@testable import SpacePilot

final class LocalizationTests: XCTestCase {
    func testNavigationUsesEnglishAndSimplifiedChinese() {
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "en")), "Overview")
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "zh-Hans")), "概览")
        XCTAssertEqual(L10n.developerAI(locale: Locale(identifier: "zh-Hans")), "开发与 AI")
    }

    func testPluginEmptyStatesAreTranslated() {
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "en")), "No Plugins installed")
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "zh-Hans")), "未安装插件")
    }
}
```

- [ ] **Step 3: Run tests and verify missing L10n failure**

```bash
swift test --filter LocalizationTests
```

Expected: compilation FAIL because `L10n` does not exist.

- [ ] **Step 4: Implement typed localized lookup**

Create `L10n.swift` with a private lookup and typed properties/functions:

```swift
import Foundation

enum L10n {
    private static func value(
        _ key: String.LocalizationValue,
        default defaultValue: String.LocalizationValue,
        locale: Locale
    ) -> String {
        String(localized: key, defaultValue: defaultValue, bundle: .module, locale: locale)
    }

    static func overview(locale: Locale = .current) -> String {
        value("nav.overview", default: "Overview", locale: locale)
    }

    static func developerAI(locale: Locale = .current) -> String {
        value("nav.developer-ai", default: "Developer & AI", locale: locale)
    }

    static func noPluginsInstalled(locale: Locale = .current) -> String {
        value("plugins.empty", default: "No Plugins installed", locale: locale)
    }
}
```

Add typed accessors for every key used in Tasks 5 and 7. Dynamic messages accept values as parameters and use localized interpolation rather than string concatenation.

- [ ] **Step 5: Create the String Catalog**

Create a valid `Localizable.xcstrings` with `sourceLanguage: "en"`, English values matching the default strings, and `zh-Hans` translations. Use this exact initial key matrix; Task 7 adds view-specific sentences discovered by the literal scan.

| Key | English | zh-Hans |
|---|---|---|
| `nav.overview` | Overview | 概览 |
| `nav.storage` | Storage | 储存空间 |
| `nav.applications` | Applications | 应用程序 |
| `nav.developer-ai` | Developer & AI | 开发与 AI |
| `nav.cleanup-history` | Cleanup History | 清理历史 |
| `common.scan` | Scan | 扫描 |
| `common.cancel` | Cancel | 取消 |
| `common.space` | Space | 空间 |
| `common.version` | Version | 版本 |
| `common.location` | Location | 位置 |
| `common.risk` | Risk | 风险 |
| `common.skills` | Skills | 技能 |
| `common.management` | Management | 管理方式 |
| `state.preparing-summary` | Preparing summary… | 正在准备摘要… |
| `state.no-data` | Run a scan to see local results. | 运行扫描以查看本机结果。 |
| `plugins.title` | Plugins | 插件 |
| `plugins.empty` | No Plugins installed | 未安装插件 |
| `plugins.discovery-failed` | Plugin discovery failed | 插件发现失败 |
| `plugins.official-handoff` | Official handoff | 由官方入口管理 |
| `risk.safe` | Safe to clean | 可安全清理 |
| `risk.rebuildable` | Rebuildable | 可重新生成 |
| `risk.sensitive` | Sensitive | 敏感数据 |
| `risk.managed` | Provider managed | 由提供方管理 |
| `category.application` | Application Data | 应用数据 |
| `category.personal` | Personal Files | 个人文件 |
| `category.developer` | Developer Files | 开发文件 |
| `category.ai-data` | AI Data | AI 数据 |
| `category.cache` | Caches | 缓存 |
| `category.log` | Logs | 日志 |
| `category.conversation` | Conversations | 对话 |
| `category.model` | Models | 模型 |
| `category.plugin` | Plugins | 插件 |
| `category.skill` | Skills | 技能 |
| `category.system` | System | 系统 |
| `category.unclassified` | Unclassified | 未分类 |

- [ ] **Step 6: Stage the SwiftPM resource bundle in the app**

After copying the executable, add to `build_and_run.sh`:

```bash
APP_RESOURCES="$APP_CONTENTS/Resources"
mkdir -p "$APP_RESOURCES"
BUILD_DIR="$(swift build --package-path "$ROOT_DIR" -c "$BUILD_CONFIGURATION" --show-bin-path)"
RESOURCE_BUNDLE="$BUILD_DIR/SpacePilot_SpacePilot.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi
```

- [ ] **Step 7: Run localization tests and inspect staged resources**

```bash
swift test --filter LocalizationTests
./script/build_and_run.sh --verify
find dist/SpacePilot.app/Contents/Resources -maxdepth 3 -type f | sort
```

Expected: tests PASS; staged bundle contains English and `zh-Hans` localization resources.

- [ ] **Step 8: Commit localization infrastructure**

```bash
git add Package.swift Sources/SpacePilot/Localization/L10n.swift Sources/SpacePilot/Resources/Localizable.xcstrings Tests/SpacePilotTests/LocalizationTests.swift script/build_and_run.sh
git commit -m "feat: add system-language localization"
```

---

### Task 7: Localize Every User-Visible Flow

**Files:**
- Modify: `Sources/SpacePilot/App/AppModel.swift`
- Modify: `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift`
- Modify: all Swift files under `Sources/SpacePilot/Views/`
- Modify: `Sources/SpacePilotCore/Models/AIApplicationTab.swift`
- Modify: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Modify: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Modify: `Tests/SpacePilotTests/LocalizationTests.swift`
- Modify: `Tests/SpacePilotCoreTests/PackageSmokeTests.swift`

**Interfaces:**
- Consumes: typed `L10n` accessors and domain enum values.
- Produces: English and Simplified Chinese for navigation, buttons, tables, states, errors, scanning, cleanup, settings, Plugins, Skills, and accessibility labels.

- [ ] **Step 1: Move display text out of Core enums**

Replace `AIApplicationTab.title`, `ItemCategory.displayName`, and `RiskLevel.displayName` UI usage with localized mappings in `L10n`:

```swift
static func title(for tab: AIApplicationTab, locale: Locale = .current) -> String
static func name(for category: ItemCategory, locale: Locale = .current) -> String
static func name(for risk: RiskLevel, locale: Locale = .current) -> String
static func name(for scope: SkillScope, locale: Locale = .current) -> String
static func name(for status: SkillManagementStatus, locale: Locale = .current) -> String
```

Keep raw enum values stable for Codable compatibility.

- [ ] **Step 2: Add translation coverage tests**

Add assertions covering every enum case:

```swift
func testEveryRiskAndCategoryHasChineseText() {
    XCTAssertTrue(RiskLevel.allCases.allSatisfy {
        !L10n.name(for: $0, locale: Locale(identifier: "zh-Hans")).isEmpty
    })
    XCTAssertTrue(ItemCategory.allCases.allSatisfy {
        !L10n.name(for: $0, locale: Locale(identifier: "zh-Hans")).isEmpty
    })
}
```

Update `PackageSmokeTests` to verify stable enum cases rather than fixed English UI titles.

- [ ] **Step 3: Replace literals in all views**

Use `Text(verbatim:)`, `Button` labels, `TableColumn`, `navigationTitle`, empty states, context menus, confirmation sheets, settings, scan status, and accessibility labels through `L10n`. Preserve product names, paths, application names, Plugin names, Skill names, and versions verbatim.

For example:

```swift
.navigationTitle(L10n.overview())
Button(L10n.scan(), systemImage: "arrow.clockwise", action: model.startScan)
TableColumn(L10n.space()) { item in
    Text(ByteCount.string(item.allocatedSize)).monospacedDigit()
}
```

- [ ] **Step 4: Localize runtime messages at presentation time**

Change scan events to carry stable stage/progress data and keep their existing diagnostic message only as a fallback. In `ScanStatusView`, map `ScanStage` to `L10n` rather than displaying persisted English directly. Convert AppModel-generated user errors such as “Quit application before uninstalling” into typed localized functions with the application name parameter.

- [ ] **Step 5: Detect remaining user-visible English literals**

```bash
rg -n 'Text\("[A-Za-z]|Button\("[A-Za-z]|Section\("[A-Za-z]|TableColumn\("[A-Za-z]|navigationTitle\("[A-Za-z]|ContentUnavailableView\("[A-Za-z]|Label\("[A-Za-z]' Sources/SpacePilot
```

Expected: no user-visible English literals; allowed matches are product names, symbols, paths, and developer diagnostics.

- [ ] **Step 6: Run localization and Core tests**

```bash
swift test --filter LocalizationTests
swift test --filter PackageSmokeTests
swift test --filter ViewProjectionTests
```

Expected: PASS.

- [ ] **Step 7: Commit full UI localization**

```bash
git add Sources/SpacePilot Sources/SpacePilotCore/Models/AIApplicationTab.swift Sources/SpacePilotCore/Models/ViewProjections.swift Sources/SpacePilotCore/Scanning/ScanCoordinator.swift Tests/SpacePilotTests Tests/SpacePilotCoreTests/PackageSmokeTests.swift
git commit -m "feat: localize spacepilot in english and chinese"
```

---

### Task 8: Verify with the Real 1 GB Snapshot

**Files:**
- Modify only if evidence identifies a specific regression in files already listed above.
- Verify: `/Users/yurunhao/Library/Application Support/SpacePilot/index.sqlite`
- Verify: `dist/SpacePilot.app`

**Interfaces:**
- Consumes: the completed implementation and existing local snapshot.
- Produces: test, build, launch, responsiveness, Plugin visibility, and language evidence.

- [ ] **Step 1: Run the full automated suite**

```bash
swift test
```

Expected: all tests PASS with zero unexpected failures.

- [ ] **Step 2: Build and launch the staged app**

```bash
./script/build_and_run.sh --verify
```

Expected: build exits 0 and `pgrep -x SpacePilot` finds the process.

- [ ] **Step 3: Verify background projection responsiveness**

With the existing snapshot loaded, use Computer Use to select these destinations twice:

1. Overview
2. Storage
3. Applications
4. Developer & AI
5. Cleanup History

For each click, confirm the selected sidebar row changes immediately or a preparation state appears. After projection completion, sample the process:

```bash
app_pid=$(pgrep -x SpacePilot | head -1)
ps -p "$app_pid" -o pid=,state=,%cpu=,%mem=,rss=,etime=
```

Expected: process returns to sleeping state with CPU near 0% after interactions; no multi-minute 100% main-thread loop.

- [ ] **Step 4: Verify real Plugins**

Run a fresh scan, then open `Developer & AI → Codex → Plugins`. Confirm at least the valid manifests found under `.codex/plugins/cache`, including `product-design`, appear with version, source, space, and Skill count. Confirm Claude does not inherit Codex Plugin rows.

- [ ] **Step 5: Verify both languages without changing application settings**

Launch once with an English process locale and once with Simplified Chinese:

```bash
pkill -x SpacePilot >/dev/null 2>&1 || true
defaults write com.yurunhao.SpacePilot AppleLanguages '(en)'
open -n dist/SpacePilot.app
pkill -x SpacePilot >/dev/null 2>&1 || true
defaults write com.yurunhao.SpacePilot AppleLanguages '(zh-Hans)'
open -n dist/SpacePilot.app
defaults delete com.yurunhao.SpacePilot AppleLanguages
```

Expected: English and Chinese navigation/UI appear respectively; deleting the app-specific override restores system-following behavior. This test changes only the app-specific language preference and restores it.

- [ ] **Step 6: Inspect diffs and repository state**

```bash
git diff --check
git status --short --branch
git log --oneline -10
```

Expected: no whitespace errors; only intentional changes are present.

- [ ] **Step 7: Commit any evidence-driven correction, then rerun verification**

If Step 3, 4, or 5 exposed a concrete failure, add one regression test, watch it fail, implement the narrow fix, rerun `swift test`, and commit only those files with:

```bash
git commit -m "fix: address acceptance verification regression"
```

If no correction was required, do not create an empty commit.

---

## Completion Checklist

- [ ] Plugin manifests decode both string and array `skills` declarations.
- [ ] Real Codex Plugins and their owned Skills are visible.
- [ ] Plugin errors produce a visible diagnostic state instead of a blank table.
- [ ] No SwiftUI view scans the full `snapshot.items` collection.
- [ ] Projection work runs off the main actor and stale results cannot publish.
- [ ] Overview, Storage, Applications, and Developer & AI use bounded or small collections.
- [ ] English and Simplified Chinese follow macOS language selection.
- [ ] The staged `.app` contains localization resources.
- [ ] Full tests pass.
- [ ] Real 1 GB snapshot navigation remains responsive.
