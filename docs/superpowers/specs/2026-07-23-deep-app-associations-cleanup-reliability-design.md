# Deep Application Associations and Cleanup Reliability Design

**Date:** 2026-07-23

**Status:** Approved for implementation

**Product:** SpacePilot for macOS 15+, Apple Silicon only

## Goal

Make application removal complete enough to find deep macOS service artifacts
without treating shared vendor data as application-owned, make every removal
choice explicit, improve cleanup reliability for live cache directories, and
add useful visual summaries to Overview.

Microsoft Edge is the acceptance fixture because it exercises exact bundle
identifiers, embedded extensions, application groups, an updater launch agent,
HTTP storage, WebKit data, crash reports, and shared Microsoft authentication
containers.

## Product Decisions

- Application removal presents the application bundle and every eligible
  related file or directory as independent checkbox rows.
- Nothing is silently added after the user confirms the list.
- Exact application-owned artifacts may be selected by the user normally.
- Shared components are visible, labeled as shared, and unselected by default.
- A shared component is never described as safe to remove while another
  installed application may still depend on it.
- Association evidence comes from application metadata before name heuristics.
- User documents and projects remain outside application-service discovery.
- Files keep strict identity and content-change checks before removal.
- A selected service directory may change internally between confirmation and
  execution without being falsely rejected, provided the directory itself is
  still the same filesystem object at the same validated path.
- All operations remain local and move approved items to the Trash.

## Deep Application Association Discovery

### Identity Graph

For each application, discovery builds an identity graph from:

- the main bundle identifier;
- identifiers of embedded app extensions, XPC services, helper applications,
  login items, and other nested bundles;
- the code-signing Team ID;
- declared application-group identifiers;
- executable and application paths referenced by launch-item property lists.

The graph is derived generically. Microsoft Edge may be used as a test fixture,
but production matching must not contain user-specific paths or a hard-coded
list that only works for Edge.

### Service Roots

The existing roots remain and discovery adds these user-library roots:

- `Library/HTTPStorages`
- `Library/WebKit`
- `Library/Application Scripts`
- `Library/Application Support/CrashReporter`
- `Library/Logs/DiagnosticReports`

Existing support for Application Support, Caches, Preferences, Logs, Saved
Application State, LaunchAgents, Containers, and Group Containers continues.
Discovery may inspect relevant children below a known service root when a
vendor directory contains the actual application directory. It must not turn
into an unrestricted home-directory or full-volume name search.

### Evidence and Confidence

Associations use the strongest available evidence:

1. **Application-owned**
   - exact main or embedded bundle identifier;
   - a launch-item plist whose executable or application path resolves into an
     application-owned support location;
   - an exact container or application-script identifier belonging to a nested
     component.
2. **Shared**
   - an application group declared by the selected application that is also
     declared by another installed application;
   - a vendor authentication, updater, or service component whose exclusive
     ownership cannot be proven.
3. **Possible**
   - vendor-and-name matches without stronger metadata evidence.

The model exposes ownership separately from cleanup risk. Confidence explains
why an item is associated; ownership determines whether it is application-only
or shared; risk determines what confirmation is required.

### Microsoft Edge Acceptance Fixture

On a Mac where the corresponding artifacts exist, Edge discovery must be able
to represent:

- `com.microsoft.edgemac` application support, caches, and preferences;
- Edge HTTP storage and WebKit data;
- Edge crash reporter metadata and diagnostic reports;
- Edge embedded-extension containers and application scripts;
- the Edge updater launch agent when its plist target proves the relationship;
- the declared `UBF8T346G9.com.microsoft.oneauth` and
  `UBF8T346G9.com.microsoft.entrabroker` group containers as shared unless
  exclusive ownership is proven.

The exact result count is filesystem-dependent. Acceptance is based on evidence
coverage and ownership correctness, not matching another product's count.

## Application Removal Review

The existing cleanup confirmation sheet becomes the single review surface for
application uninstall and reset.

Each row contains:

- a checkbox;
- the Finder file or folder icon;
- item name and exact path;
- relationship label and evidence;
- ownership or shared warning;
- risk and allocated size.

The application bundle is a distinct row. Related directories are not collapsed
into one all-or-nothing application total. The initial selection policy is:

- preserve the existing global rule that cleanup review starts empty;
- shared and possible associations remain unselected when “Select All” is used
  unless the user explicitly selects them;
- sensitive items continue to require the separate sensitive-data
  acknowledgement.

The application detail list also uses Finder icons and shows owned, shared, and
possible associations rather than presenting all related items as equivalent.

## File and Folder Icons

A shared SwiftUI file-icon component obtains native icons through
`NSWorkspace`. It:

- displays the actual application icon for app bundles;
- displays native folder and document-type icons for filesystem items;
- uses an SF Symbol fallback when the path no longer exists;
- caches resolved images so scrolling does not repeatedly request icons;
- provides a non-color accessibility label and does not perform filesystem
  enumeration.

The component is used in application associations, cleanup review, Storage item
rows, and other existing file lists where it improves identification.

## Overview Visualizations

Overview gains two native Swift Charts visualizations above the recommendation
list:

1. **Internal disk capacity**
   - donut chart for used and available capacity;
   - exact used, available, and total values in text;
   - clearly represents the whole internal disk.
2. **Locally analyzed categories**
   - ranked horizontal bars for non-empty analyzed categories;
   - category name and allocated size in text;
   - explicitly labeled as analyzed coverage so it is not confused with the
     whole-volume breakdown.

Charts are accessibility-enhanced summaries, not replacements for numeric
labels. They use semantic adaptive colors, support Light and Dark mode, and
remain compact enough that recommendations stay visible in a normal window.

`OverviewProjection` supplies bounded category totals and disk capacity values;
views do not aggregate the full snapshot on the main actor.

## Cleanup Reliability

### Root Cause

The current executor compares a selected directory's recursive allocated size
and modification date with an old scan snapshot. Live caches can legitimately
change for hours between scanning and cleanup, causing safe selections to be
reported as changed even though the selected directory is still the same
filesystem object.

Cleanup history currently stores only candidate IDs and result text, so an old
failure cannot identify the affected source path.

### Revalidation Rules

Cleanup planning refreshes selected candidates immediately before execution.
Path safety is validated before and during execution.

- For a regular file, verify type, canonical path, resource identifier,
  allocated size, and modification date.
- For a directory, verify type, canonical path, and the directory's resource
  identifier. Do not require its recursive contents or aggregate size to remain
  frozen.
- If the filesystem object was replaced, changed type, disappeared, escaped
  the allowed volume, or resolves to a protected path, skip it.
- A failed or skipped item never contributes to verified reclaimed bytes.

This preserves time-of-check/time-of-use protection while allowing explicitly
selected cache directories to receive normal writes.

### Cleanup History

New cleanup outcomes persist enough immutable context to explain the operation:

- source URL;
- displayed source size at execution planning time;
- relationship explanation;
- outcome status and localized reason;
- resulting Trash URL when available.

New fields are optional when decoding so existing history records remain
readable. History shows the path and distinguishes changed identity, protected
path, missing item, permission failure, and other mover failures.

## Performance and Safety

- Metadata extraction and directory traversal run off the main actor.
- Known service-root traversal is bounded and cancellation-aware.
- Code-signing metadata is cached per application scan.
- Application association projection remains bounded to discovered service
  roots rather than scanning arbitrary personal files.
- Shared artifacts count once in global storage totals even if multiple
  applications reference them.
- Cleanup actions continue through `PathSafetyPolicy`, explicit selection,
  Trash movement, transaction persistence, and post-action rescan.

## Localization and Accessibility

English and Simplified Chinese strings are added for:

- owned, shared, and possible relationship labels;
- shared-component warnings;
- chart titles, capacity values, and analyzed-coverage explanation;
- detailed cleanup failure reasons and history source paths.

`L10n.allKeys`, both `.strings` files, and `Localizable.xcstrings` remain
synchronized. Checkbox rows, icons, chart summaries, and relationship warnings
receive meaningful accessibility labels.

## Verification

- Resolver tests cover deep roots, embedded identifiers, application groups,
  launch-item target parsing, nested vendor directories, and cancellation.
- Multi-application tests prove a shared App Group is never classified as
  application-owned.
- Edge fixture tests cover all acceptance categories without depending on the
  current user's home path.
- Uninstall planner tests prove application bundle and related items remain
  independently selectable.
- Cleanup tests prove:
  - changed or replaced files are skipped;
  - a replaced directory is skipped;
  - a directory whose contents change but whose identity is stable can move;
  - history records the source path and remains backward compatible.
- Projection tests cover disk and analyzed-category chart data.
- UI architecture and localization parity tests pass.
- The full Swift test suite and arm64 macOS 15 release script pass.
- Runtime validation checks Edge association presentation, selective uninstall,
  native icons, both Overview charts, and a cleanup of a live test cache.

## Non-Goals

- Matching another cleaner's raw association count regardless of ownership.
- Automatically removing shared authentication, keychain, or vendor data.
- Reading browser content, cookies, history, credentials, or document contents.
- Installing a privileged helper or deleting protected system-wide artifacts.
- Permanent deletion or bypassing the Trash.
