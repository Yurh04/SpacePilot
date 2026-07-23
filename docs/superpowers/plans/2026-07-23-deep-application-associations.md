# Deep Application Associations and Selective Uninstall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Discover deep application service artifacts from verifiable macOS metadata and present application-owned, shared, and possible items as individually selectable uninstall rows with native icons.

**Architecture:** Build a reusable identity index for all installed applications, then resolve known user-library service roots against main bundle IDs, embedded component IDs, App Groups, and launch-item targets. Persist ownership independently from confidence and risk; projections and cleanup review preserve that evidence.

**Tech Stack:** Swift 6, Foundation, Security framework signing metadata, AppKit `NSWorkspace`, SwiftUI, XCTest.

## Global Constraints

- Minimum OS is macOS 15 and the build supports Apple Silicon only.
- Production rules are generic and contain no user-specific absolute path or Edge-only hard-coded result list.
- Discovery remains within known service roots and never searches personal documents.
- Shared components are visible but never represented as application-owned.
- Existing snapshots remain decodable after model additions.
- All UI remains English/Simplified Chinese and follows macOS system language.

---

### Task 1: Model association ownership

**Files:**
- Modify: `Sources/SpacePilotCore/Models/ApplicationRecord.swift`
- Modify: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Test: `Tests/SpacePilotCoreTests/ModelAggregationTests.swift`

**Interfaces:**
- Consumes: existing `AssociationEvidence`, `AssociationConfidence`, and `RiskLevel`.
- Produces: `AssociationOwnership`, backward-compatible `ArtifactAssociation.ownership`, and projection access to ownership.

- [ ] **Step 1: Write a legacy-decode test**

```swift
func testArtifactAssociationDefaultsLegacyOwnershipToPossible() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001",
     "itemID":"00000000-0000-0000-0000-000000000002",
     "applicationID":"00000000-0000-0000-0000-000000000003",
     "evidence":"vendorAndNameMatch","confidence":60,"risk":"rebuildable"}
    """.data(using: .utf8)!
    let association = try JSONDecoder().decode(ArtifactAssociation.self, from: json)
    XCTAssertEqual(association.ownership, .possible)
}
```

- [ ] **Step 2: Run the test and verify compilation failure**

Run:

```bash
swift test --filter ModelAggregationTests.testArtifactAssociationDefaultsLegacyOwnershipToPossible
```

Expected: compilation fails because `AssociationOwnership` does not exist.

- [ ] **Step 3: Add ownership with custom legacy decoding**

```swift
public enum AssociationOwnership: String, Codable, Sendable {
    case owned
    case shared
    case possible
}
```

Add `ownership` to `ArtifactAssociation`. Implement `init(from:)` using
`decodeIfPresent(AssociationOwnership.self, forKey: .ownership) ?? .possible`
and encode every field including ownership. Update the initializer to require
an explicit ownership so new call sites cannot silently choose one.

- [ ] **Step 4: Run model and persistence tests**

Run:

```bash
swift test --filter ModelAggregationTests
swift test --filter SQLiteIndexStoreTests
```

Expected: both suites pass after existing fixtures provide explicit ownership.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Models/ApplicationRecord.swift Sources/SpacePilotCore/Models/ViewProjections.swift Tests/SpacePilotCoreTests/ModelAggregationTests.swift Tests
git commit -m "feat: distinguish owned and shared app artifacts"
```

---

### Task 2: Extract installed-application identity metadata

**Files:**
- Create: `Sources/SpacePilotCore/Applications/ApplicationIdentity.swift`
- Create: `Sources/SpacePilotCore/Applications/ApplicationIdentityReader.swift`
- Modify: `Package.swift`
- Test: `Tests/SpacePilotCoreTests/ApplicationIdentityReaderTests.swift`
- Test: `Tests/SpacePilotCoreTests/Fixtures/TestAppBuilder.swift`

**Interfaces:**
- Consumes: `ApplicationRecord.url` and standard bundle layout.
- Produces: `ApplicationIdentity` and protocol `ApplicationIdentityReading.read(application:)`.

- [ ] **Step 1: Create fixture bundles and failing identity tests**

Build a test app containing `Contents/PlugIns/Widget.appex` and assert:

```swift
func testReadsMainEmbeddedAndApplicationGroupIdentifiers() throws {
    let app = try TestAppBuilder(name: "Browser", bundleIdentifier: "com.example.browser")
        .withEmbeddedBundle(
            relativePath: "Contents/PlugIns/Widget.appex",
            bundleIdentifier: "com.example.browser.widget"
        )
        .build()
    let signing = StubSigningMetadata(
        teamIdentifier: "TEAM123",
        applicationGroups: ["TEAM123.com.example.shared"]
    )
    let identity = try ApplicationIdentityReader(signingReader: signing)
        .read(application: app.record)

    XCTAssertEqual(identity.mainBundleIdentifier, "com.example.browser")
    XCTAssertTrue(identity.componentBundleIdentifiers.contains("com.example.browser.widget"))
    XCTAssertEqual(identity.teamIdentifier, "TEAM123")
    XCTAssertEqual(identity.applicationGroups, ["TEAM123.com.example.shared"])
}
```

- [ ] **Step 2: Run the focused tests and verify missing types**

Run:

```bash
swift test --filter ApplicationIdentityReaderTests
```

Expected: compilation fails because the identity reader types do not exist.

- [ ] **Step 3: Implement the value model and signing-reader boundary**

```swift
public struct ApplicationIdentity: Sendable {
    public let applicationID: UUID
    public let mainBundleIdentifier: String?
    public let componentBundleIdentifiers: Set<String>
    public let teamIdentifier: String?
    public let applicationGroups: Set<String>

    public var allBundleIdentifiers: Set<String> {
        var result = componentBundleIdentifiers
        if let mainBundleIdentifier { result.insert(mainBundleIdentifier) }
        return result
    }
}

public protocol ApplicationSigningMetadataReading: Sendable {
    func metadata(at applicationURL: URL) throws -> ApplicationSigningMetadata
}
```

The live reader uses `SecStaticCodeCreateWithPath` and
`SecCodeCopySigningInformation` to read `kSecCodeInfoTeamIdentifier` and
`kSecCodeInfoEntitlementsDict`. Add `.linkedFramework("Security")` to
`SpacePilotCore`.

- [ ] **Step 4: Implement bounded embedded-bundle discovery**

Enumerate only `Contents/PlugIns`, `Contents/XPCServices`,
`Contents/Library/LoginItems`, and `Contents/Helpers`. Read each discovered
`.app`, `.appex`, or `.xpc` bundle's `CFBundleIdentifier`; do not descend into
arbitrary resources.

- [ ] **Step 5: Run identity tests**

Run:

```bash
swift test --filter ApplicationIdentityReaderTests
```

Expected: main ID, embedded ID, Team ID, and App Groups all pass.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/SpacePilotCore/Applications/ApplicationIdentity.swift Sources/SpacePilotCore/Applications/ApplicationIdentityReader.swift Tests/SpacePilotCoreTests/ApplicationIdentityReaderTests.swift Tests/SpacePilotCoreTests/Fixtures/TestAppBuilder.swift
git commit -m "feat: read application identity metadata"
```

---

### Task 3: Resolve deep service roots and shared ownership

**Files:**
- Modify: `Sources/SpacePilotCore/Applications/ApplicationRule.swift`
- Modify: `Sources/SpacePilotCore/Applications/ApplicationArtifactResolver.swift`
- Modify: `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift`
- Test: `Tests/SpacePilotCoreTests/ApplicationArtifactResolverTests.swift`
- Test: `Tests/SpacePilotCoreTests/ScanCoordinatorTests.swift`

**Interfaces:**
- Consumes: `[ApplicationIdentity]` from Task 2.
- Produces: batch `resolve(applications:identities:homeDirectory:)` with deduplicated items and per-application associations.

- [ ] **Step 1: Add deep-root and shared-group tests**

Use two application identities sharing one group and assert:

```swift
func testSharedApplicationGroupIsNotOwnedByEitherApplication() async throws {
    let home = try TemporaryTree(files: [
        "Library/Group Containers/TEAM.shared/token.db": 64
    ])
    let first = application(id: UUID(), name: "First", bundleID: "com.example.first")
    let second = application(id: UUID(), name: "Second", bundleID: "com.example.second")
    let identities = [
        identity(for: first, groups: ["TEAM.shared"]),
        identity(for: second, groups: ["TEAM.shared"])
    ]

    let result = try await ApplicationArtifactResolver().resolve(
        applications: [first, second],
        identities: identities,
        homeDirectory: home.url
    )

    let associations = result.resolutions.flatMap(\.associations)
    XCTAssertEqual(associations.count, 2)
    XCTAssertTrue(associations.allSatisfy { $0.ownership == .shared })
}
```

Add fixtures for HTTPStorages, WebKit, Application Scripts, CrashReporter,
DiagnosticReports, an embedded component container, and a nested
`Application Support/Vendor/Product` directory.

- [ ] **Step 2: Run resolver tests and verify failure**

Run:

```bash
swift test --filter ApplicationArtifactResolverTests
```

Expected: the batch resolver signature and deep-root results are missing.

- [ ] **Step 3: Add the new known service roots**

Append:

```swift
.init(relativePath: "Library/HTTPStorages", category: .application, risk: .sensitive),
.init(relativePath: "Library/WebKit", category: .cache, risk: .rebuildable),
.init(relativePath: "Library/Application Scripts", category: .application, risk: .sensitive),
.init(relativePath: "Library/Application Support/CrashReporter", category: .log, risk: .rebuildable),
.init(relativePath: "Library/Logs/DiagnosticReports", category: .log, risk: .rebuildable)
```

- [ ] **Step 4: Implement batch matching and deduplication**

Build `groupOwnerCounts` once:

```swift
let groupOwnerCounts = identities
    .flatMap { $0.applicationGroups }
    .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
```

Match in this priority:

```swift
if identity.allBundleIdentifiers.contains(component)
    || identity.allBundleIdentifiers.contains(stem) {
    return Match(evidence: .exactBundleIdentifier, confidence: .high, ownership: .owned)
}
if identity.applicationGroups.contains(component) {
    let isExclusive = groupOwnerCounts[component, default: 0] == 1
        && identity.allBundleIdentifiers.contains { component.contains($0) }
    let ownership: AssociationOwnership = isExclusive ? .owned : .shared
    return Match(evidence: .exactContainerIdentifier, confidence: .high, ownership: ownership)
}
if normalizedComponent == normalizedApplicationName {
    return Match(evidence: .vendorAndNameMatch, confidence: .medium, ownership: .possible)
}
```

Traverse at most two directory levels below service roots that conventionally
contain vendor folders. Once a parent is matched, do not emit matched
descendants as duplicate cleanup items.

- [ ] **Step 5: Integrate the identity index into scanning**

Read all identities once after `baseApplications`, call the batch resolver,
then rebuild `ApplicationRecord.associations` by application ID. Preserve item
deduplication by canonical path in `ScanCoordinator`.

- [ ] **Step 6: Run resolver and coordinator tests**

Run:

```bash
swift test --filter ApplicationArtifactResolverTests
swift test --filter ScanCoordinatorTests
```

Expected: all deep-root, shared-group, cancellation, and snapshot integration
tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SpacePilotCore/Applications/ApplicationRule.swift Sources/SpacePilotCore/Applications/ApplicationArtifactResolver.swift Sources/SpacePilotCore/Scanning/ScanCoordinator.swift Tests/SpacePilotCoreTests/ApplicationArtifactResolverTests.swift Tests/SpacePilotCoreTests/ScanCoordinatorTests.swift
git commit -m "feat: discover deep application service files"
```

---

### Task 4: Parse launch-item targets and verify the Edge fixture

**Files:**
- Create: `Sources/SpacePilotCore/Applications/LaunchItemAssociationReader.swift`
- Modify: `Sources/SpacePilotCore/Applications/ApplicationArtifactResolver.swift`
- Create: `Tests/SpacePilotCoreTests/Fixtures/EdgeAssociationFixture.swift`
- Modify: `Tests/SpacePilotCoreTests/ApplicationArtifactResolverTests.swift`

**Interfaces:**
- Consumes: application identities, known support paths, and LaunchAgent plist URLs.
- Produces: `LaunchItemAssociationReader.targetURLs(in:)` and `.signedHelperRelationship` associations.

- [ ] **Step 1: Write launch-target and Edge fixture tests**

Create a plist with `ProgramArguments[0]` pointing to a fixture
`Library/Application Support/Vendor/BrowserUpdater/Updater.app/...` and assert
the launch agent and updater support directory are associated, but unrelated
vendor items are not.

The Edge fixture must assert categories rather than a fixed count:

```swift
XCTAssertTrue(paths.contains { $0.hasSuffix("Library/HTTPStorages/com.microsoft.edgemac") })
XCTAssertTrue(paths.contains { $0.hasSuffix("Library/WebKit/com.microsoft.edgemac") })
XCTAssertTrue(paths.contains { $0.hasSuffix("Library/Application Scripts/com.microsoft.edgemac.wdgExtension") })
XCTAssertEqual(ownership["UBF8T346G9.com.microsoft.oneauth"], .shared)
XCTAssertEqual(ownership["UBF8T346G9.com.microsoft.entrabroker"], .shared)
```

- [ ] **Step 2: Run the Edge fixture and verify failure**

Run:

```bash
swift test --filter ApplicationArtifactResolverTests
```

Expected: launch-item target and some Edge categories are absent.

- [ ] **Step 3: Implement safe plist target extraction**

```swift
public struct LaunchItemAssociationReader: Sendable {
    public init() {}

    public func targetURLs(in plistURL: URL) -> [URL] {
        guard let data = try? Data(contentsOf: plistURL),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = value as? [String: Any]
        else { return [] }
        let program = dictionary["Program"] as? String
        let firstArgument = (dictionary["ProgramArguments"] as? [String])?.first
        return [program, firstArgument]
            .compactMap { $0 }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }
}
```

Only associate targets contained by known application-support roots and linked
to the selected identity or unique normalized product name. Ambiguous vendor
updaters are `.shared` or `.possible`, never `.owned`.

- [ ] **Step 4: Run resolver tests**

Run:

```bash
swift test --filter ApplicationArtifactResolverTests
```

Expected: the generic launch-agent and Edge category tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Applications/LaunchItemAssociationReader.swift Sources/SpacePilotCore/Applications/ApplicationArtifactResolver.swift Tests/SpacePilotCoreTests/Fixtures/EdgeAssociationFixture.swift Tests/SpacePilotCoreTests/ApplicationArtifactResolverTests.swift
git commit -m "feat: associate application launch services"
```

---

### Task 5: Preserve ownership in uninstall selection

**Files:**
- Modify: `Sources/SpacePilotCore/Applications/ApplicationUninstallPlanner.swift`
- Modify: `Sources/SpacePilot/Views/Shared/CleanupSelection.swift`
- Modify: `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`
- Test: `Tests/SpacePilotCoreTests/ApplicationUninstallPlannerTests.swift`
- Test: `Tests/SpacePilotTests/CleanupSelectionTests.swift`

**Interfaces:**
- Consumes: association ownership from Tasks 1–4.
- Produces: `CleanupReviewItem` carrying a `ScannedItem` plus ownership/evidence presentation metadata.

- [ ] **Step 1: Write failing independent-selection tests**

Assert the bundle and each association are separate rows, and that Select All
excludes shared and possible rows:

```swift
func testSelectAllIncludesOnlyOwnedReviewItems() {
    var selection = CleanupSelection(items: [
        reviewItem(ownership: .owned),
        reviewItem(ownership: .shared),
        reviewItem(ownership: .possible)
    ])
    selection.selectAll()
    XCTAssertEqual(selection.selectedIDs, [selection.items[0].id])
}
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
swift test --filter ApplicationUninstallPlannerTests
swift test --filter CleanupSelectionTests
```

Expected: review metadata does not exist and Select All selects every row.

- [ ] **Step 3: Add the review value and update planners**

```swift
public struct CleanupReviewItem: Identifiable, Sendable {
    public var id: UUID { item.id }
    public let item: ScannedItem
    public let ownership: AssociationOwnership
    public let evidence: AssociationEvidence?

    public var isIncludedBySelectAll: Bool { ownership == .owned }
}
```

The application bundle is `.owned` with no association evidence. Include all
non-managed associations in uninstall review, not only high-confidence ones;
ownership controls selection behavior. Reset continues to exclude sensitive,
managed, shared, and possible items.

- [ ] **Step 4: Update confirmation state and AppModel adapters**

Make `CleanupSelection` consume `[CleanupReviewItem]`; ordinary Storage cleanup
wraps items as `.owned`, while application uninstall passes association
metadata. Confirmation still sends only selected underlying `ScannedItem.id`
values to `CleanupPlanner`.

- [ ] **Step 5: Run selection and planner tests**

Run:

```bash
swift test --filter ApplicationUninstallPlannerTests
swift test --filter CleanupSelectionTests
swift test --filter ApplicationCleanupArchitectureTests
```

Expected: rows are independent, initial selection is empty, Select All excludes
shared/possible rows, and only explicit IDs reach cleanup planning.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpacePilotCore/Applications/ApplicationUninstallPlanner.swift Sources/SpacePilot/Views/Shared/CleanupSelection.swift Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift Sources/SpacePilot/App/AppModel.swift Tests/SpacePilotCoreTests/ApplicationUninstallPlannerTests.swift Tests/SpacePilotTests
git commit -m "feat: review every uninstall artifact independently"
```

---

### Task 6: Add native file icons and ownership presentation

**Files:**
- Create: `Sources/SpacePilot/Views/Shared/FileSystemItemIcon.swift`
- Modify: `Sources/SpacePilot/Views/Shared/StorageItemRow.swift`
- Modify: `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`
- Modify: `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`
- Modify: `Sources/SpacePilot/Localization/L10n.swift`
- Modify: `Sources/SpacePilot/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Test: `Tests/SpacePilotTests/ApplicationCleanupArchitectureTests.swift`
- Test: `Tests/SpacePilotTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: URLs, ownership, evidence, and review items from Task 5.
- Produces: reusable `FileSystemItemIcon` and localized ownership rows.

- [ ] **Step 1: Add architecture and localization tests**

Assert all three file lists use `FileSystemItemIcon`, and required ownership
keys exist in both languages.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter ApplicationCleanupArchitectureTests
swift test --filter LocalizationTests
```

Expected: icon component and ownership localization keys are absent.

- [ ] **Step 3: Implement cached native icons**

```swift
@MainActor
private final class FileIconCache {
    static let shared = FileIconCache()
    private let images: NSCache<NSString, NSImage>

    private init() {
        images = NSCache()
        images.countLimit = 512
    }

    func image(for url: URL) -> NSImage {
        let key = url.standardizedFileURL.path as NSString
        if let image = images.object(forKey: key) { return image }
        let image = NSWorkspace.shared.icon(forFile: key as String)
        images.setObject(image, forKey: key)
        return image
    }
}

struct FileSystemItemIcon: View {
    let url: URL
    var size: CGFloat = 20

    var body: some View {
        Image(nsImage: FileIconCache.shared.image(for: url))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 4: Add icons and relationship labels**

Place the icon before file/folder names in application detail, cleanup review,
and Storage rows. Show localized “Application-owned,” “Shared component,” or
“Possible association,” plus existing evidence and risk. Shared warnings use
text and a warning symbol, not color alone.

- [ ] **Step 5: Run UI and localization tests**

Run:

```bash
swift test --filter ApplicationCleanupArchitectureTests
swift test --filter LocalizationTests
```

Expected: architecture and localization parity tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpacePilot/Views Sources/SpacePilot/Localization/L10n.swift Sources/SpacePilot/Resources Tests/SpacePilotTests
git commit -m "feat: show native icons and app ownership"
```
