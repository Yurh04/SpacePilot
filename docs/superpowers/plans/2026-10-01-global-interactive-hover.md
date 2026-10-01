# Global Interactive Hover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every clearly clickable SpacePilot surface a consistent, layout-stable macOS hover response while preserving native control behavior, selection, double-click, context menus, and keyboard interaction.

**Architecture:** Keep standard SwiftUI controls on their native hover behavior. Add a shared SwiftUI modifier for custom/plain clickable surfaces, plus a narrow AppKit adapter that highlights the complete interactive row underneath SwiftUI `List` and `Table`. Page code opts in explicitly so non-interactive metrics, headers, and informational content never appear clickable.

**Tech Stack:** Swift 6, SwiftUI, AppKit interoperability, Swift Package Manager, Swift Testing/XCTest, macOS 15+.

**Spec:** `docs/superpowers/specs/2026-10-01-global-interactive-hover-design.md`

## Global Constraints

- Preserve all unrelated changes in the dirty working tree. Stage only the files named by the current task before each commit; when a task overlaps an already-dirty file, use `git add -p` and inspect `git diff --cached` so the commit contains only this feature's hunks.
- Do not add dependencies, private API calls, system-class-name matching, global event monitors, or application-level hover state.
- Do not add hover decoration to plain text, read-only metrics, charts, section labels, or other non-clickable content.
- Do not replace the macOS arrow cursor with a pointing-hand cursor.
- Hover decoration must not change ideal size, padding, alignment, row height, selection, focus, accessibility role, or hit target.
- Disabled and selected states take precedence over hover; system button, menu, picker, toggle, toolbar, and sidebar selection visuals remain native.
- Table/list hover work must coexist with `NativeTableDoubleClickAdapter`, context menus, keyboard selection, and grouped visible-row mapping.
- Hover work must not trigger storage scanning, projection rebuilding, persistence writes, or full-data traversal.
- If a stable public route to the backing `NSTableView` cannot be maintained, stop and return to the approved design instead of relying on private SwiftUI internals.

## Review Focus

1. Reused table rows never retain a stale hover background after scrolling or data reloads.
2. Group headers and collapsed rows use visible-row mapping and never become clickable-looking by flat-index accident.
3. Selected rows keep the system selection appearance when the pointer enters or exits.
4. Disabled custom controls cannot show hover feedback.
5. Installing both native adapters leaves existing target/action, double-click, context-menu, and keyboard behavior intact.

---

### Task 1: Add the shared SwiftUI hover primitive

**Files:**
- Create: `Sources/SpacePilot/Views/Shared/InteractiveHover.swift`
- Create: `Tests/SpacePilotTests/InteractiveHoverTests.swift`

**Interfaces:**
- Produces: `View.interactiveHover(isEnabled:cornerRadius:)` for an already-clickable custom surface.
- Uses: environment `isEnabled`, `accessibilityReduceMotion`, and semantic `Color.accentColor` only.
- Does not produce: click handling, selection handling, cursor changes, or expanded hit targets.

- [ ] **Step 1: Write failing state and sizing tests**

Add focused tests for a small internal, pure state resolver and a hosted-view sizing assertion:

```swift
func testHoverIsVisibleOnlyWhenPointerAndBothEnablementSourcesAllowIt()
func testReduceMotionUsesNoAnimatedTransition()
func testModifierDoesNotChangeIdealSize()
```

The state matrix must cover pointer outside, explicit disablement, environment disablement, and enabled pointer-inside. The sizing test should compare an `NSHostingView` around the same fixed-size label before and after applying the modifier.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
swift test --filter InteractiveHoverTests
```

Expected: compilation fails because `InteractiveHoverState` and `interactiveHover` do not exist.

- [ ] **Step 3: Implement the modifier without layout movement**

Create these internal interfaces:

```swift
struct InteractiveHoverState: Equatable {
    static func resolve(
        isHovering: Bool,
        explicitEnabled: Bool,
        environmentEnabled: Bool,
        reduceMotion: Bool
    ) -> InteractiveHoverState
}

extension View {
    func interactiveHover(
        isEnabled: Bool = true,
        cornerRadius: CGFloat = 8
    ) -> some View
}
```

Use overlay/background layers so the modifier adds no padding or frame. Use accent-color fill near `0.08` opacity, an optional 1 pt low-opacity stroke, and a 120 ms `easeOut` transition only when Reduce Motion is off. Drive local pointer state with `onHover`; combine explicit and environment enablement before showing any decoration.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
swift test --filter InteractiveHoverTests
```

Expected: the state matrix, Reduce Motion branch, and ideal-size regression all pass.

- [ ] **Step 5: Commit only the shared primitive**

```bash
git add Sources/SpacePilot/Views/Shared/InteractiveHover.swift Tests/SpacePilotTests/InteractiveHoverTests.swift
git commit -m "feat: add shared interactive hover styling"
```

---

### Task 2: Add a native whole-row hover adapter for List and Table

**Files:**
- Create: `Sources/SpacePilot/Views/Shared/NativeTableSupport.swift`
- Create: `Sources/SpacePilot/Views/Shared/NativeTableHover.swift`
- Modify: `Sources/SpacePilot/Views/Shared/NativeTableDoubleClick.swift`
- Create: `Tests/SpacePilotTests/NativeTableHoverTests.swift`
- Modify: `Tests/SpacePilotTests/FinderRevealTests.swift`

**Interfaces:**
- Produces: `View.nativeTableHoverHighlight(isRowInteractive:)`.
- Shares: a public-framework-only nearest-`NSTableView` lookup with the double-click adapter.
- Consumes: an optional visible-row predicate; the predicate receives `NSTableView` row coordinates, not a model-array index.

- [ ] **Step 1: Extract and lock down shared native-table discovery**

Move the existing nearest-table traversal out of `NativeTableDoubleClick.swift` into `NativeTableSupport.swift` without changing its behavior. Update the existing double-click tests to assert that attaching/detaching the adapter still preserves the original target, action, and double action.

- [ ] **Step 2: Write failing hover coordinator tests**

Create fixtures using a real `NSTableView` and explicit rows. Add tests named along these lines:

```swift
func testPointerMapsToInteractiveVisibleRow()
func testNonInteractiveAndGroupRowsDoNotHighlight()
func testSelectedRowKeepsSystemSelectionAppearance()
func testMovingBetweenRowsClearsOnlyThePreviousRow()
func testExitReloadScrollAndDismantleClearHoverState()
func testHoverAndDoubleClickAdaptersPreserveExistingActions()
```

The row-reuse test must scroll or recycle visible row views and prove that no recycled view keeps the temporary background. The coexistence test must install both adapters on the same table.

- [ ] **Step 3: Run native adapter tests and verify RED**

Run:

```bash
swift test --filter NativeTableHoverTests
swift test --filter NativeTableDoubleClickCoordinatorTests
```

Expected: the new hover tests fail to compile while all pre-existing double-click tests still pass after the discovery extraction.

- [ ] **Step 4: Implement bounded tracking and cleanup**

Add these interfaces:

```swift
struct NativeTableHoverAdapter: NSViewRepresentable {
    let isRowInteractive: (Int) -> Bool
}

extension View {
    func nativeTableHoverHighlight(
        isRowInteractive: @escaping (Int) -> Bool = { _ in true }
    ) -> some View
}
```

The coordinator must own only weak table references, its tracking area/observers, and the current hovered row. Convert pointer coordinates through the table, reject `row == -1`, group rows, selected rows, and predicate failures, then invalidate only the old and new visible rows. Clear temporary state on mouse exit, bounds/row changes, reload notification, selection changes, and dismantle. Restore only decoration the adapter itself applied; never replace table target/action or selection drawing.

- [ ] **Step 5: Run native adapter regression tests and verify GREEN**

Run:

```bash
swift test --filter NativeTableHoverTests
swift test --filter NativeTableDoubleClickCoordinatorTests
```

Expected: row mapping, group exclusion, selection precedence, reuse cleanup, lifecycle cleanup, and dual-adapter action preservation all pass.

- [ ] **Step 6: Commit only native-table infrastructure**

```bash
git add Sources/SpacePilot/Views/Shared/NativeTableSupport.swift \
  Sources/SpacePilot/Views/Shared/NativeTableHover.swift \
  Sources/SpacePilot/Views/Shared/NativeTableDoubleClick.swift \
  Tests/SpacePilotTests/NativeTableHoverTests.swift \
  Tests/SpacePilotTests/FinderRevealTests.swift
git commit -m "feat: add native table row hover feedback"
```

---

### Task 3: Cover application, storage, cleanup, and history rows

**Files:**
- Modify: `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`
- Modify: `Sources/SpacePilot/Views/Storage/StorageView.swift`
- Modify: `Sources/SpacePilot/Views/History/CleanupHistoryView.swift`
- Modify: `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`
- Modify: `Tests/SpacePilotTests/ApplicationCleanupArchitectureTests.swift`
- Modify: `Tests/SpacePilotTests/StorageWorkbenchArchitectureTests.swift`
- Create: `Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift`

**Interfaces:**
- Applies: whole-row hover only to rows that already select, reveal, expand, or invoke an action.
- Excludes: empty states, read-only summaries, table headers, and selection-disabled rows.

- [ ] **Step 1: Write failing source-coverage assertions**

In `InteractiveHoverCoverageTests`, enumerate the concrete view files in this task and assert that each relevant `List`/`Table` composition installs `nativeTableHoverHighlight`. Add negative assertions for known read-only metric and capacity components so a broad wrapper cannot accidentally make them hoverable.

- [ ] **Step 2: Run page architecture tests and verify RED**

Run:

```bash
swift test --filter InteractiveHoverCoverageTests
swift test --filter ApplicationCleanupArchitectureTests
swift test --filter StorageWorkbenchArchitectureTests
```

Expected: coverage assertions fail because the page modifiers are absent; existing behavior tests remain green.

- [ ] **Step 3: Attach hover at each native collection boundary**

Place `nativeTableHoverHighlight` beside the existing list/table style and double-click modifiers. For filtered/sorted data, derive interactivity from the exact visible collection used to render the rows. Do not wrap entire cards or scroll views. Add `interactiveHover(cornerRadius: 6)` only to the application search clear button because it is `.buttonStyle(.plain)` and lacks native bordered feedback.

- [ ] **Step 4: Verify page behavior and architecture**

Run:

```bash
swift test --filter InteractiveHoverCoverageTests
swift test --filter ApplicationCleanupArchitectureTests
swift test --filter StorageWorkbenchArchitectureTests
swift test --filter FinderRevealTests
```

Expected: all listed suites pass; Finder reveal/double-click behavior is unchanged.

- [ ] **Step 5: Commit only these page integrations**

```bash
git add -p Sources/SpacePilot/Views/Applications/ApplicationsView.swift \
  Sources/SpacePilot/Views/Storage/StorageView.swift \
  Sources/SpacePilot/Views/History/CleanupHistoryView.swift \
  Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift \
  Tests/SpacePilotTests/ApplicationCleanupArchitectureTests.swift \
  Tests/SpacePilotTests/StorageWorkbenchArchitectureTests.swift
git add Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift
git diff --cached
git commit -m "feat: add hover feedback to storage workflows"
```

---

### Task 4: Cover Developer & AI rows and custom clickable cards

**Files:**
- Modify: `Sources/SpacePilot/Views/DeveloperAI/DeveloperAIView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/AIManagementOverviewView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/AIApplicationDetailView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/AIAgentDetailView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/MCPServersView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/GlobalSkillsView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/GlobalPluginsView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/CLIToolsView.swift`
- Modify: `Sources/SpacePilot/Views/DeveloperAI/OtherAIToolsView.swift`
- Modify: `Tests/SpacePilotTests/AIWorkspacePresentationTests.swift`
- Modify: `Tests/SpacePilotTests/DeveloperAIArchitectureTests.swift`
- Modify: `Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift`

**Interfaces:**
- Applies: `interactiveHover` to the custom agent cards and the selection-disabled expand/collapse button.
- Applies: `nativeTableHoverHighlight` to Developer & AI lists/tables using each view's visible-row mapping.
- Preserves: selected agent rows, collapsed group structure, Finder reveal, and all read-only asset summaries.

- [ ] **Step 1: Add failing Developer & AI coverage tests**

Extend the architecture tests to require:

- the `.buttonStyle(.plain)` agent card uses `interactiveHover(cornerRadius: 10)`;
- the selection-disabled group toggle uses `interactiveHover` but visible group headers without actions do not;
- every native list/table file named above installs `nativeTableHoverHighlight`;
- grouped and collapsed lists pass an explicit visible-row predicate rather than accepting the default all-rows predicate.

- [ ] **Step 2: Run focused tests and verify RED**

Run:

```bash
swift test --filter AIWorkspacePresentationTests
swift test --filter DeveloperAIArchitectureTests
swift test --filter InteractiveHoverCoverageTests
```

Expected: new coverage checks fail on missing modifiers and visible-row predicates.

- [ ] **Step 3: Implement grouped visible-row interactivity first**

Reuse or add pure visible-row mapping helpers for each grouped/collapsed list. Model section/group header rows explicitly; do not index `allAgents`, skills, plugins, or assets directly with an `NSTableView` row. Pass the resulting predicate to `nativeTableHoverHighlight` so only actionable visible rows highlight.

- [ ] **Step 4: Apply custom-surface hover without double decoration**

Add `interactiveHover` after `.buttonStyle(.plain)` for agent cards and the group expand/collapse control. Leave `.bordered`, `.borderless`, menu, picker, toggle, and standard toolbar buttons on native feedback unless the button label itself is a custom card surface. Do not apply both shared hover systems to the same row.

- [ ] **Step 5: Run Developer & AI regression tests and verify GREEN**

Run:

```bash
swift test --filter AIWorkspacePresentationTests
swift test --filter DeveloperAIArchitectureTests
swift test --filter InteractiveHoverCoverageTests
swift test --filter FinderRevealTests
```

Expected: custom-card and row coverage pass; collapsed headers stay excluded; reveal and selection tests remain green.

- [ ] **Step 6: Commit only Developer & AI integration**

```bash
git add -p Sources/SpacePilot/Views/DeveloperAI \
  Tests/SpacePilotTests/AIWorkspacePresentationTests.swift \
  Tests/SpacePilotTests/DeveloperAIArchitectureTests.swift \
  Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift
git diff --cached
git commit -m "feat: add hover feedback to developer workflows"
```

---

### Task 5: Audit remaining top-level clickable surfaces

**Files:**
- Modify if required: `Sources/SpacePilot/Views/Overview/OverviewView.swift`
- Modify if required: `Sources/SpacePilot/Views/SidebarView.swift`
- Modify if required: `Sources/SpacePilot/Views/AppRootView.swift`
- Modify: `Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift`
- Modify if required: `Tests/SpacePilotTests/OverviewChartArchitectureTests.swift`
- Modify if required: `Tests/SpacePilotTests/SidebarRuntimeLayoutTests.swift`

**Interfaces:**
- Keeps: native hover for the main sidebar, bordered overview actions, search, picker, toggle, menu, and toolbar controls.
- Adds: shared hover only where the audit finds a custom/plain clickable surface without a visible native response.

- [ ] **Step 1: Inventory all clickable declarations**

Run:

```bash
rg -n 'Button|NavigationLink|onTapGesture|simultaneousGesture|buttonStyle|contextMenu' Sources/SpacePilot/Views --glob '*.swift'
```

Classify every result as native control, native table/list row, custom clickable surface, context-menu-only surface, or non-clickable decoration. Record the file-level coverage set in `InteractiveHoverCoverageTests` so later pages cannot silently omit the shared behavior.

- [ ] **Step 2: Add a failing test for each true gap**

Only add a source-coverage assertion when a clickable surface has neither native feedback nor one of the shared hover mechanisms. Add negative assertions ensuring overview metrics/charts and root layout containers stay undecorated.

- [ ] **Step 3: Make the minimum page edits**

Apply `interactiveHover` only to confirmed custom/plain gaps. Do not add custom decoration to `SidebarView` if the native sidebar selection/hover remains visible. Preserve the horizontal recent-changes metrics and all existing responsive layout constraints.

- [ ] **Step 4: Run top-level UI tests**

Run:

```bash
swift test --filter InteractiveHoverCoverageTests
swift test --filter OverviewChartArchitectureTests
swift test --filter SidebarRuntimeLayoutTests
```

Expected: the explicit coverage inventory passes and existing overview/sidebar layout tests remain green.

- [ ] **Step 5: Commit the final page audit**

Stage only hunks actually changed in this task. Because these files may already
contain unrelated edits, use patch staging and verify the staged diff:

```bash
git add -p Sources/SpacePilot/Views/Overview/OverviewView.swift \
  Sources/SpacePilot/Views/SidebarView.swift \
  Sources/SpacePilot/Views/AppRootView.swift \
  Tests/SpacePilotTests/InteractiveHoverCoverageTests.swift \
  Tests/SpacePilotTests/OverviewChartArchitectureTests.swift \
  Tests/SpacePilotTests/SidebarRuntimeLayoutTests.swift
git diff --cached
git commit -m "test: enforce interactive hover coverage"
```

Omit untouched paths from `git add`; do not stage unrelated pre-existing edits.

---

### Task 6: Update project facts and complete full verification

**Files:**
- Modify: `docs/PROJECT_STATUS.md`
- Modify: `docs/FEATURE_MATRIX.md`
- Modify: `docs/CURRENT_WORK.md`

**Interfaces:**
- Documents: the new shared hover primitives, exact automated checks, and runtime verification state.
- Does not claim: release readiness or runtime coverage that was not actually verified.

- [ ] **Step 1: Run the complete automated suite**

Run:

```bash
swift test
./script/test_release.sh
```

Expected: all tests and release checks pass. If either command fails, record the exact failure and fix only regressions caused by this feature before continuing.

- [ ] **Step 2: Build and launch the real application**

Run:

```bash
./script/build_and_run.sh
```

Check light and dark appearances at the normal window width and at approximately `806x760`. With a mouse or trackpad, inspect Overview, Storage, Applications, Developer & AI, and Cleanup History.

The manual checklist must verify:

- custom cards and plain controls fade in/out without resizing;
- native controls do not show doubled backgrounds;
- whole table/list rows highlight, not isolated cells;
- selected rows keep their system selection color;
- grouped headers and disabled controls remain unchanged;
- scrolling/reloading does not leave stale row backgrounds;
- single click, double click, context menu, keyboard navigation, and Finder reveal still work.

- [ ] **Step 3: Update the current project documents with evidence**

Record the feature, test counts/results, release-check result, and both tested window sizes. If manual verification is blocked, write that limitation to `docs/CURRENT_WORK.md` rather than marking the work complete.

- [ ] **Step 4: Review the final diff against the approved spec**

Run:

```bash
git diff --check
git diff --stat
git status --short
```

Confirm every item under **Review Focus** has a named automated test, all clickable-surface categories from the spec are accounted for, and unrelated dirty files remain unstaged and unmodified by this feature.

- [ ] **Step 5: Commit documentation only after verification**

```bash
git add -p docs/PROJECT_STATUS.md docs/FEATURE_MATRIX.md docs/CURRENT_WORK.md
git diff --cached
git commit -m "docs: record interactive hover verification"
```

---

## Final Acceptance Checklist

- [ ] Every custom clickable surface without adequate native feedback uses `interactiveHover`.
- [ ] Every interactive `List`/`Table` ordinary row has whole-row hover feedback.
- [ ] Non-clickable information, group headers, selected rows, and disabled controls never acquire misleading hover styling.
- [ ] No hover transition changes layout or cursor shape.
- [ ] Native selection, focus, double click, context menu, keyboard operation, and Finder reveal remain intact.
- [ ] Row reuse, reload, scroll, mouse exit, and teardown clear temporary native decoration.
- [ ] `swift test` and `./script/test_release.sh` pass.
- [ ] Real-app checks pass in light/dark mode at normal and narrow window sizes.
- [ ] Project status documents reflect only verified facts.
