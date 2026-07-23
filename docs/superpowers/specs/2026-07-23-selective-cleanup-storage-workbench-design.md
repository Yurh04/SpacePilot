# Selective Cleanup and Storage Workbench Design

**Date:** 2026-07-23

**Status:** Approved for implementation

**Product:** SpacePilot for macOS 15+, Apple Silicon only

## Goal

Turn cleanup review into a safe, item-by-item decision and turn Storage from a
passive pair of tables into a connected analysis workspace that answers:

1. How full is the internal disk?
2. Which analyzed categories occupy the most space?
3. Which concrete items make up a selected category?
4. Which selected items are safe to review for cleanup?

## Product Decisions

- Cleanup review starts with **no items selected**.
- The user can select or deselect every candidate independently.
- “Select All” and “Clear” are explicit secondary actions.
- The primary cleanup action always states the selected item count and size.
- Sensitive selected items still require a separate confirmation.
- Managed items remain ineligible for direct cleanup.
- Storage uses one selection-driven workspace instead of two unrelated tables.
- All analysis stays local and all existing English/Simplified Chinese behavior
  continues to follow the macOS system language.

## Cleanup Review

### Layout

The sheet contains:

1. Title and reversible-to-Trash explanation.
2. A compact toolbar with candidate count, “Select All,” and “Clear.”
3. A list where every row has a checkbox, name, exact path, risk, explanation,
   and allocated size.
4. A sticky summary showing selected count and selected bytes.
5. Existing Trash acknowledgement.
6. Sensitive-data acknowledgement only when at least one selected item is
   sensitive.
7. Cancel and “Move Selected to Trash” actions.

### State and Safety

- Initial selected IDs are an empty set.
- Selection is local to the sheet and discarded when the sheet closes.
- The primary action is disabled when:
  - no item is selected;
  - the Trash acknowledgement is off;
  - a selected sensitive item has not been separately confirmed; or
  - cleanup is executing.
- Only selected IDs are sent to `CleanupPlanner`.
- Selected-byte totals use `allocatedSize`.

## Storage Workbench

### Information Architecture

The page has three connected regions:

1. **Disk overview**
   - total capacity;
   - used capacity;
   - available capacity;
   - locally analyzed bytes;
   - a native capacity progress indicator.

2. **Category browser**
   - an “All analyzed items” entry;
   - one row per non-empty category;
   - localized category name, item count, allocated size, and proportional
     progress;
   - selecting a row filters the item table immediately.

3. **Item workspace**
   - “Largest” and “Older than 180 days” modes;
   - current category title and matching item count;
   - a multi-select table with name, location, risk, and allocated size;
   - an always-visible “Review Safe Cleanup” action for selected safe items;
   - a selected-item detail region with full path, localized risk/explanation,
     modification date when available, Reveal in Finder, and cleanup review for
     a safe item.

### Projection

`StorageProjection` provides bounded data suitable for synchronous SwiftUI
rendering:

- total, used, available, and analyzed byte counts;
- category summaries;
- global largest/old items;
- largest/old items grouped by `ItemCategory`.

Each visible collection remains bounded to 100 items. Category grouping
therefore has a strict upper bound of `100 × ItemCategory.allCases.count`.
Search filters the already bounded visible result and never traverses the full
snapshot on the main actor.

### Selection Rules

- The initial category is “All analyzed items.”
- Changing category or display mode clears stale item selection.
- Search preserves only selections still visible in the filtered result.
- Batch cleanup includes only selected `.safe` items.
- Sensitive, rebuildable, and managed rows remain inspectable but are not
  silently added to the safe-cleanup batch.
- Context menus remain as a secondary shortcut; primary actions stay visible.

## Accessibility and macOS Conventions

- Use native `List`, `Table`, `ProgressView`, buttons, toggles, and selection
  bindings.
- Do not rely on color alone; every capacity, risk, and selection state has text.
- Checkboxes have item-specific accessibility labels.
- Buttons have explicit localized labels and disabled states.
- Keyboard navigation follows native table/list behavior.
- Existing semantic colors and adaptive system materials remain unchanged.

## Localization

Add English and Simplified Chinese strings for:

- disk capacity metrics;
- “All analyzed items”;
- selected item/byte summaries;
- “Select All” and “Clear”;
- storage detail labels and empty states;
- visible safe-cleanup actions.

`L10n.allKeys`, both `.strings` files, and `Localizable.xcstrings` must remain
exactly synchronized.

## Verification

- Unit tests prove cleanup selection defaults to empty and totals only selected
  items.
- Unit tests prove Storage projection metrics and category-specific largest/old
  results.
- Unit tests prove selected IDs, not all candidates, are sent to cleanup
  planning.
- Localization parity tests pass for both supported languages.
- Full Swift test suite passes.
- The staged app builds for `arm64-apple-macosx15.0`, signs successfully, and
  launches.
- Runtime inspection verifies category-to-table filtering, row selection,
  cleanup-sheet selection, and disabled/enabled primary action states.
