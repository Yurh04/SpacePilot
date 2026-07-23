# Overview Storage Charts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add accessible native charts that distinguish whole-disk capacity from locally analyzed category usage.

**Architecture:** Extend `OverviewProjection` with bounded disk-capacity and category-summary values computed off the main actor. Render a compact Swift Charts donut and ranked horizontal bar chart while retaining exact text values and the existing recommendation workflow.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, XCTest.

## Global Constraints

- Minimum OS is macOS 15 and the build supports Apple Silicon only.
- Charts never imply analyzed categories account for the entire internal disk.
- Exact numeric text remains available and charts do not rely on color alone.
- Existing recommendation selection and cleanup behavior remain unchanged.
- English and Simplified Chinese continue to follow macOS system language.

---

### Task 1: Project chart-ready disk and category data

**Files:**
- Modify: `Sources/SpacePilotCore/Models/ViewProjections.swift`
- Test: `Tests/SpacePilotCoreTests/ViewProjectionTests.swift`

**Interfaces:**
- Consumes: `ScanSnapshot.volume`, applications, and scanned items.
- Produces: `OverviewProjection.totalCapacityBytes`, `availableBytes`, and bounded `categories`.

- [ ] **Step 1: Write failing projection tests**

```swift
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
    XCTAssertEqual(projection.categories.map(\.category), [.personal, .cache])
}
```

Also assert empty categories are omitted, ordering is descending, and the
collection is bounded by `ItemCategory.allCases.count`.

- [ ] **Step 2: Run the test and verify missing properties**

Run:

```bash
swift test --filter ViewProjectionTests.testOverviewProjectsDiskCapacityAndAnalyzedCategories
```

Expected: compilation fails because the chart projection properties are absent.

- [ ] **Step 3: Aggregate chart values in the projection**

Add:

```swift
public let totalCapacityBytes: Int64
public let availableBytes: Int64
public let categories: [StorageCategorySummary]
```

Use one pass over items:

```swift
var categoryTotals: [ItemCategory: (bytes: Int64, count: Int)] = [:]
for item in snapshot.items {
    try checkpoint.checkPeriodically()
    itemBytes += item.allocatedSize
    categoryTotals[item.category, default: (0, 0)].bytes += item.allocatedSize
    categoryTotals[item.category, default: (0, 0)].count += 1
    // existing recommendation logic remains here
}
categories = categoryTotals.map {
    StorageCategorySummary(category: $0.key, allocatedSize: $0.value.bytes, itemCount: $0.value.count)
}.sorted { $0.allocatedSize > $1.allocatedSize }
```

Set capacity and available values from `snapshot.volume`, with safe fallbacks
when volume metadata is unavailable.

- [ ] **Step 4: Run projection tests**

Run:

```bash
swift test --filter ViewProjectionTests
```

Expected: all projection tests pass and cancellation checkpoints remain active.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Models/ViewProjections.swift Tests/SpacePilotCoreTests/ViewProjectionTests.swift
git commit -m "feat: project overview chart metrics"
```

---

### Task 2: Render accessible native charts

**Files:**
- Create: `Sources/SpacePilot/Views/Overview/DiskCapacityChart.swift`
- Create: `Sources/SpacePilot/Views/Overview/AnalyzedCategoryChart.swift`
- Modify: `Sources/SpacePilot/Views/Overview/OverviewView.swift`
- Modify: `Sources/SpacePilot/Localization/L10n.swift`
- Modify: `Sources/SpacePilot/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Create: `Tests/SpacePilotTests/OverviewChartArchitectureTests.swift`
- Modify: `Tests/SpacePilotTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: chart-ready `OverviewProjection` from Task 1.
- Produces: `DiskCapacityChart` and `AnalyzedCategoryChart`.

- [ ] **Step 1: Write failing architecture and localization tests**

Assert `OverviewView` composes both chart types, both files import `Charts`, and
the localized chart titles and coverage explanation exist in both languages.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
swift test --filter OverviewChartArchitectureTests
swift test --filter LocalizationTests
```

Expected: chart files and localization keys are missing.

- [ ] **Step 3: Implement the disk-capacity donut**

```swift
import Charts
import SpacePilotCore
import SwiftUI

struct DiskCapacityChart: View {
    let usedBytes: Int64
    let availableBytes: Int64

    private struct CapacitySegment: Identifiable {
        var id: String { name }
        let name: String
        let bytes: Int64
    }

    var body: some View {
        Chart([
            CapacitySegment(name: L10n.text(.overviewDiskUsed), bytes: usedBytes),
            CapacitySegment(name: L10n.text(.overviewDiskAvailable), bytes: availableBytes)
        ]) { segment in
            SectorMark(
                angle: .value(L10n.text(.space), segment.bytes),
                innerRadius: .ratio(0.64),
                angularInset: 1
            )
            .foregroundStyle(by: .value(L10n.text(.category), segment.name))
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .accessibilityLabel(L10n.text(.overviewDiskCapacityChart))
        .accessibilityValue(
            "\(L10n.text(.overviewDiskUsed)) \(ByteCount.string(usedBytes)), "
            + "\(L10n.text(.overviewDiskAvailable)) \(ByteCount.string(availableBytes))"
        )
    }
}
```

Keep exact used, available, and total text beside the chart.

- [ ] **Step 4: Implement ranked analyzed-category bars**

Use horizontal `BarMark` values from `projection.categories`, a localized
category axis, and an accessibility representation listing each category and
size. The section description must say these bars cover locally analyzed data,
not the whole disk.

- [ ] **Step 5: Compose charts without hiding recommendations**

Place both charts in the first Overview section with a responsive
`ViewThatFits`: side-by-side above 900 points and vertically stacked in narrower
windows. Cap chart height at 220 points and keep recommendation rows directly
below.

- [ ] **Step 6: Run architecture and localization tests**

Run:

```bash
swift test --filter OverviewChartArchitectureTests
swift test --filter LocalizationTests
```

Expected: chart composition and localization parity tests pass.

- [ ] **Step 7: Commit**

```bash
git add Sources/SpacePilot/Views/Overview Sources/SpacePilot/Localization/L10n.swift Sources/SpacePilot/Resources Tests/SpacePilotTests
git commit -m "feat: add overview storage charts"
```

---

### Task 3: Integrated verification

**Files:**
- Modify only files required by failures found during verification.

**Interfaces:**
- Consumes: all completed tasks from the three 2026-07-23 implementation plans.
- Produces: a tested arm64 macOS 15 build and runtime evidence for the approved design.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: all tests pass with zero failures.

- [ ] **Step 2: Run release validation**

Run:

```bash
./script/test_release.sh
```

Expected: arm64 and macOS 15 checks pass; ad hoc Gatekeeper rejection remains
the expected result until Developer ID signing is configured.

- [ ] **Step 3: Launch and validate runtime behavior**

Build and launch the app, scan, then verify:

- Edge shows deep owned, shared, and possible associations with correct icons.
- Uninstall review permits individual selection and does not include shared
  items in Select All.
- Overview displays both charts with correct text in Chinese and English system
  locales.
- A controlled live cache directory can change internally and still move to
  Trash.
- Cleanup History shows the attempted source path and exact result.

- [ ] **Step 4: Commit verification-only fixes**

If verification required code changes, commit only those validated changes:

```bash
git status --short
git add Sources/SpacePilot Sources/SpacePilotCore Tests/SpacePilotTests Tests/SpacePilotCoreTests
git commit -m "fix: polish deep cleanup workflow"
```

If no files changed, record the passing commands in the final handoff without
creating an empty commit.
