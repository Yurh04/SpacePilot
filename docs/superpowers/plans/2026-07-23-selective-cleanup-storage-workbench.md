# Selective Cleanup and Storage Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add item-by-item cleanup selection and replace the passive Storage tables with a category-driven, actionable storage workspace.

**Architecture:** Extend the bounded `StorageProjection` with disk metrics and per-category item collections, keep cleanup selection as a small pure value type in the app target, and let SwiftUI own only transient category/row selections. `AppModel` remains the sole owner of cleanup execution and receives the exact selected IDs from the confirmation sheet.

**Tech Stack:** Swift 6, SwiftUI for macOS 15, Observation, Swift Package Manager, XCTest, Foundation/AppKit, existing SpacePilotCore projection and cleanup layers.

## Global Constraints

- Support Apple Silicon only.
- Minimum operating system is macOS 15.
- Analysis remains local and metadata-only.
- English and Simplified Chinese follow the macOS system language.
- Cleanup defaults to no selected items and moves only explicitly selected IDs to Trash.
- Managed items are never offered for direct cleanup.
- Main-actor Storage rendering operates only on bounded projection collections.

---

### Task 1: Storage Projection Metrics and Category Collections

**Files:**
- Modify: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Modify: `Tests/SpacePilotCoreTests/ViewProjectionTests.swift`

**Interfaces:**
- Produces: `StorageProjection.totalCapacity: Int64`
- Produces: `StorageProjection.usedBytes: Int64`
- Produces: `StorageProjection.availableBytes: Int64`
- Produces: `StorageProjection.analyzedBytes: Int64`
- Produces: `StorageProjection.largestItemsByCategory: [ItemCategory: [ScannedItem]]`
- Produces: `StorageProjection.oldItemsByCategory: [ItemCategory: [ScannedItem]]`
- Produces: `StorageProjection.items(category: ItemCategory?, oldOnly: Bool) -> [ScannedItem]`

- [ ] **Step 1: Write failing projection tests**

Add tests that build a snapshot with cache, developer, old, and recent items:

```swift
func testStorageProjectionPublishesDiskMetricsAndCategoryItems() throws {
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
```

Extend the bounded-output test:

```swift
XCTAssertLessThanOrEqual(
    projection.storage.largestItemsByCategory.values.flatMap { $0 }.count,
    StorageProjection.itemDisplayLimit * ItemCategory.allCases.count
)
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter ViewProjectionTests/testStorageProjectionPublishesDiskMetricsAndCategoryItems
```

Expected: compilation fails because the new `StorageProjection` metrics and
category API do not exist.

- [ ] **Step 3: Implement bounded metrics and category selections**

Add stored properties to `StorageProjection`, populate a pair of
`BoundedScannedItemSelection` values per category during the existing single
item loop, and expose:

```swift
public func items(category: ItemCategory?, oldOnly: Bool) -> [ScannedItem] {
    guard let category else {
        return oldOnly ? oldItems : largestItems
    }
    return oldOnly
        ? oldItemsByCategory[category, default: []]
        : largestItemsByCategory[category, default: []]
}
```

When a volume exists, use its capacity values. Without a volume, use analyzed
item/application bytes for total and used, and zero for available. Do not add
residual system bytes to `analyzedBytes`.

- [ ] **Step 4: Run projection tests and verify GREEN**

Run:

```bash
swift test --filter ViewProjectionTests
```

Expected: all `ViewProjectionTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Models/ViewProjections.swift Tests/SpacePilotCoreTests/ViewProjectionTests.swift
git commit -m "feat: project storage metrics by category"
```

### Task 2: Pure Cleanup Selection State

**Files:**
- Create: `Sources/SpacePilot/Views/Shared/CleanupSelection.swift`
- Create: `Tests/SpacePilotTests/CleanupSelectionTests.swift`

**Interfaces:**
- Produces: `CleanupSelection.init(items: [ScannedItem])`
- Produces: `CleanupSelection.selectedIDs: Set<UUID>`
- Produces: `CleanupSelection.selectedItems: [ScannedItem]`
- Produces: `CleanupSelection.selectedBytes: Int64`
- Produces: `CleanupSelection.hasSelectedSensitiveItems: Bool`
- Produces: `CleanupSelection.toggle(_ id: UUID)`
- Produces: `CleanupSelection.selectAll()`
- Produces: `CleanupSelection.clear()`

- [ ] **Step 1: Write failing selection tests**

```swift
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class CleanupSelectionTests: XCTestCase {
    func testSelectionStartsEmptyAndTotalsOnlyExplicitSelections() throws {
        let safe = ScannedItem.fixture(path: "/tmp/safe", risk: .safe, allocatedSize: 100)
        let sensitive = ScannedItem.fixture(
            path: "/tmp/sensitive",
            risk: .sensitive,
            allocatedSize: 300
        )
        var selection = CleanupSelection(items: [safe, sensitive])

        XCTAssertTrue(selection.selectedIDs.isEmpty)
        XCTAssertEqual(selection.selectedBytes, 0)
        XCTAssertFalse(selection.hasSelectedSensitiveItems)

        selection.toggle(sensitive.id)

        XCTAssertEqual(selection.selectedItems.map(\.id), [sensitive.id])
        XCTAssertEqual(selection.selectedBytes, 300)
        XCTAssertTrue(selection.hasSelectedSensitiveItems)
    }

    func testSelectAllAndClearStayWithinCandidates() {
        let items = [
            ScannedItem.fixture(path: "/tmp/one"),
            ScannedItem.fixture(path: "/tmp/two")
        ]
        var selection = CleanupSelection(items: items)

        selection.selectAll()
        XCTAssertEqual(selection.selectedIDs, Set(items.map(\.id)))

        selection.clear()
        XCTAssertTrue(selection.selectedIDs.isEmpty)
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter CleanupSelectionTests
```

Expected: compilation fails because `CleanupSelection` does not exist.

- [ ] **Step 3: Implement the minimal selection value**

Create a value type that stores the immutable candidates and a mutable ID set:

```swift
struct CleanupSelection {
    let items: [ScannedItem]
    private(set) var selectedIDs: Set<UUID> = []

    var selectedItems: [ScannedItem] {
        items.filter { selectedIDs.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedItems.reduce(0) { $0 + $1.allocatedSize }
    }

    var hasSelectedSensitiveItems: Bool {
        selectedItems.contains { $0.risk == .sensitive }
    }

    mutating func toggle(_ id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        if !selectedIDs.insert(id).inserted {
            selectedIDs.remove(id)
        }
    }

    mutating func selectAll() {
        selectedIDs = Set(items.map(\.id))
    }

    mutating func clear() {
        selectedIDs.removeAll()
    }
}
```

- [ ] **Step 4: Run selection tests and verify GREEN**

Run:

```bash
swift test --filter CleanupSelectionTests
```

Expected: 2 tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilot/Views/Shared/CleanupSelection.swift Tests/SpacePilotTests/CleanupSelectionTests.swift
git commit -m "feat: model explicit cleanup selection"
```

### Task 3: Execute Only Selected Cleanup Candidates

**Files:**
- Modify: `Sources/SpacePilot/App/AppModel.swift`
- Modify: `Sources/SpacePilot/Views/AppRootView.swift`
- Modify: `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`
- Create: `Tests/SpacePilotTests/CleanupSelectionArchitectureTests.swift`

**Interfaces:**
- Changes: `CleanupConfirmationView.onConfirm` to `(Set<UUID>, Bool) -> Void`
- Changes: `AppModel.executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool)`

- [ ] **Step 1: Write failing architecture tests**

Add source-architecture assertions that read `AppModel.swift` and
`CleanupConfirmationView.swift` from the repository:

```swift
func testPreparedCleanupUsesExplicitSelectedIDs() throws {
    let model = try String(contentsOf: repositoryRoot.appending(
        path: "Sources/SpacePilot/App/AppModel.swift"
    ))
    XCTAssertTrue(model.contains(
        "func executePreparedCleanup(selectedIDs: Set<UUID>, confirmSensitive: Bool)"
    ))
    XCTAssertTrue(model.contains("selectedIDs: selectedIDs"))
    XCTAssertFalse(model.contains("selectedIDs: Set(cleanupCandidates.map(\\.id))"))
}

func testCleanupConfirmationStartsWithSelectionModelAndDisablesEmptyConfirm() throws {
    let view = try String(contentsOf: repositoryRoot.appending(
        path: "Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift"
    ))
    XCTAssertTrue(view.contains("@State private var selection: CleanupSelection"))
    XCTAssertTrue(view.contains("selection.selectedIDs.isEmpty"))
    XCTAssertTrue(view.contains("selection.toggle(item.id)"))
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter CleanupSelectionArchitectureTests
```

Expected: assertions fail because cleanup still sends every candidate ID.

- [ ] **Step 3: Update model and sheet wiring**

Change the model method to accept selected IDs, intersect them with current
candidate IDs, guard against an empty intersection, and pass exactly that set to
`CleanupPlanner`. Build separately confirmed sensitive IDs from selected
sensitive candidates only.

Initialize `CleanupSelection` in `CleanupConfirmationView.init`, render a native
checkbox for each row, add Select All/Clear buttons and a selected summary, and
call:

```swift
onConfirm(selection.selectedIDs, confirmsSensitive)
```

The primary button disabled expression must include:

```swift
selection.selectedIDs.isEmpty
    || !understandsTrash
    || (selection.hasSelectedSensitiveItems && !confirmsSensitive)
    || isExecuting
```

- [ ] **Step 4: Run focused and full app-target tests**

Run:

```bash
swift test --filter CleanupSelection
```

Expected: all cleanup-selection behavior and architecture tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilot/App/AppModel.swift Sources/SpacePilot/Views/AppRootView.swift Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift Tests/SpacePilotTests/CleanupSelectionArchitectureTests.swift
git commit -m "feat: choose cleanup items individually"
```

### Task 4: Category-Driven Storage Workbench

**Files:**
- Modify: `Sources/SpacePilot/Views/Storage/StorageView.swift`
- Create: `Tests/SpacePilotTests/StorageWorkbenchArchitectureTests.swift`

**Interfaces:**
- Consumes: `StorageProjection.items(category:oldOnly:)`
- Consumes: disk metrics added by Task 1
- Produces: `StorageCategorySelection` with `.all` and `.category(ItemCategory)`

- [ ] **Step 1: Write failing storage-workbench architecture tests**

```swift
func testStorageViewConnectsCategoryAndTableSelection() throws {
    let source = try String(contentsOf: repositoryRoot.appending(
        path: "Sources/SpacePilot/Views/Storage/StorageView.swift"
    ))
    XCTAssertTrue(source.contains("@State private var categorySelection"))
    XCTAssertTrue(source.contains("@State private var selectedItemIDs"))
    XCTAssertTrue(source.contains("projection.items("))
    XCTAssertTrue(source.contains("Table(selection: $selectedItemIDs)"))
    XCTAssertTrue(source.contains("safeSelectedItems"))
}

func testStorageViewShowsDiskMetricsAndVisibleCleanupAction() throws {
    let source = try String(contentsOf: repositoryRoot.appending(
        path: "Sources/SpacePilot/Views/Storage/StorageView.swift"
    ))
    XCTAssertTrue(source.contains("projection.totalCapacity"))
    XCTAssertTrue(source.contains("projection.availableBytes"))
    XCTAssertTrue(source.contains("ProgressView("))
    XCTAssertTrue(source.contains("reviewCleanup(safeSelectedItems)"))
}
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter StorageWorkbenchArchitectureTests
```

Expected: assertions fail because the current categories table is not connected
to the lower table and has no visible batch action.

- [ ] **Step 3: Build the selection-driven SwiftUI layout**

Refactor `StorageView` into focused private subviews in the same file:

- `StorageCapacityHeader`
- `StorageCategoryBrowser`
- `StorageItemsWorkspace`
- `StorageItemDetail`

Use a top capacity header and an `HSplitView` below it. The left side is a native
category `List(selection:)`; the right side owns the mode picker, visible batch
cleanup button, multi-select `Table(selection:)`, and selected-item details.
Compute visible items only from:

```swift
projection.items(
    category: categorySelection.category,
    oldOnly: mode == .old
)
```

then apply `searchText`. Compute `safeSelectedItems` by intersecting visible
selected IDs with rows whose risk is `.safe`. Clear `selectedItemIDs` when the
category or mode changes.

- [ ] **Step 4: Run focused tests and compile**

Run:

```bash
swift test --filter StorageWorkbenchArchitectureTests
swift build
```

Expected: architecture tests pass and the app compiles without warnings.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilot/Views/Storage/StorageView.swift Tests/SpacePilotTests/StorageWorkbenchArchitectureTests.swift
git commit -m "feat: connect storage categories to actions"
```

### Task 5: English and Simplified Chinese Copy

**Files:**
- Modify: `Sources/SpacePilot/Localization/L10n.swift`
- Modify: `Sources/SpacePilot/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Modify: `Tests/SpacePilotTests/LocalizationTests.swift`

**Interfaces:**
- Produces localized copy for disk metrics, category selection, selected
  summaries, cleanup selection actions, and storage details.

- [ ] **Step 1: Write failing localization tests**

Add assertions for representative English and Chinese copy:

```swift
func testSelectiveCleanupAndStorageWorkbenchUseBothLanguages() {
    let english = Locale(identifier: "en")
    let chinese = Locale(identifier: "zh-Hans")

    XCTAssertEqual(L10n.text(.cleanupSelectAll, locale: english), "Select All")
    XCTAssertEqual(L10n.text(.cleanupSelectAll, locale: chinese), "全选")
    XCTAssertEqual(L10n.text(.storageAllAnalyzed, locale: english), "All Analyzed Items")
    XCTAssertEqual(L10n.text(.storageAllAnalyzed, locale: chinese), "全部已分析项目")
    XCTAssertEqual(L10n.selectedItems(2, space: "3 GB", locale: chinese), "已选 2 项，共 3 GB")
}
```

Update the catalog count assertion to the exact new `L10n.allKeys.count`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter LocalizationTests/testSelectiveCleanupAndStorageWorkbenchUseBothLanguages
```

Expected: compilation fails because the new copy keys and formatter do not
exist.

- [ ] **Step 3: Add synchronized localization entries**

Add typed `L10n.Copy` values and one formatted selected-items helper. Add every
key to `allKeys`, both `.strings` tables, and `Localizable.xcstrings` with exact
matching values. Use concise native desktop copy:

- English: “Select All”, “Clear”, “All Analyzed Items”, “Review Safe Cleanup”,
  “Total Capacity”, “Used”, “Available”, “Analyzed Locally”.
- Chinese: “全选”, “清除”, “全部已分析项目”, “检查安全清理”, “总容量”,
  “已使用”, “可用”, “本地已分析”.

- [ ] **Step 4: Run localization parity tests**

Run:

```bash
swift test --filter LocalizationTests
```

Expected: all localization and staged-resource tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilot/Localization/L10n.swift Sources/SpacePilot/Resources Tests/SpacePilotTests/LocalizationTests.swift
git commit -m "feat: localize storage cleanup workflow"
```

### Task 6: Full Verification and Runtime UX Pass

**Files:**
- Modify if necessary: files changed by Tasks 1–5
- Verify: `script/build_and_run.sh`

**Interfaces:**
- Verifies the complete feature without adding new product scope.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: every test passes with no failures or unexpected warnings.

- [ ] **Step 2: Verify the Apple Silicon macOS 15 release artifact**

Run:

```bash
./script/test_release.sh
```

Expected: the arm64 macOS 15 release build, staging, localization, and signature
checks pass.

- [ ] **Step 3: Launch the fresh app**

Run:

```bash
./script/build_and_run.sh --verify
```

Expected: SpacePilot builds, launches, and the process verification succeeds.

- [ ] **Step 4: Inspect the core runtime flow**

Using the running app:

1. Open Storage.
2. Confirm total/used/available/analyzed metrics are visible.
3. Select a category and confirm the table changes to that category.
4. Change Largest/Older mode and confirm stale row selection clears.
5. Select a safe item and confirm the visible cleanup action becomes enabled.
6. Open cleanup review and confirm no checkbox is initially selected.
7. Select one row and confirm count/bytes and button state update.
8. Clear selection and confirm the primary action disables.
9. Switch macOS app language between English and Simplified Chinese and inspect
   the new labels.

- [ ] **Step 5: Commit verification fixes**

If runtime inspection required corrections, run the focused failing test first,
make the minimal correction, rerun the full suite, then commit:

```bash
git add Sources Tests
git commit -m "fix: polish storage cleanup workflow"
```

If no corrections were required, do not create an empty commit.
