# SpacePilot Design Specification

Date: 2026-07-22

Status: Approved for implementation

## 1. Product Summary

SpacePilot is a native macOS utility for understanding internal storage usage, safely uninstalling applications, and explaining the local footprint of AI applications. It is designed for ordinary Mac users while providing unusually deep visibility into developer tools, AI application data, Plugins, and Skills.

The product has two equal primary jobs:

1. Explain what consumes storage and help the user safely reclaim space.
2. Remove applications together with related files without silently deleting user-created content.

Its primary differentiation is an AI application asset view. A user selects an AI application such as Codex or Claude and sees its data footprint, Plugins, and Skills in one place, with each asset's real source and scope preserved.

## 2. Product Principles

- Local only: scanning, classification, and recommendations run entirely on the Mac.
- Explain before acting: every recommendation exposes its path, origin, risk, and expected effect.
- Reversible by default: sensitive or user-owned files go to the Trash; permanent deletion is not a first-version workflow.
- Read-only scanning: scanners never mutate the filesystem.
- Separate action gate: cleanup actions are created as explicit plans, revalidated, confirmed, executed, and verified.
- No fake certainty: unknown formats or low-confidence associations are displayed as unknown and are not recommended for removal.
- Simple interface: one native sidebar, one primary workspace, one accent color, and minimal card chrome.

## 3. Target Platform and Distribution

- Minimum OS: macOS 15 Sequoia.
- CPU: Apple Silicon only.
- Language: Swift 6.
- UI: SwiftUI first, with narrow AppKit interop only where macOS APIs require it.
- Distribution: direct download from the product website as a signed and notarized DMG or ZIP.
- Signing: Developer ID Application with Hardened Runtime.
- Mac App Store is not a first-version target because App Sandbox restrictions conflict with broad storage inspection and application cleanup.
- Network services and user accounts are not required.

## 4. First-Version Scope

### 4.1 Storage Analysis

- Scan the internal system volume and the current user's accessible data.
- Show used, available, and potentially reclaimable capacity.
- Classify usage into applications, personal files, developer and AI data, and system or unclassified data.
- Find large files and directories.
- Find old downloads and other long-unused content using metadata only.
- Provide quick results first, then progressively refine them with targeted scans.
- Show scan coverage and explicitly mark areas that could not be read.

### 4.2 Application Management

- Inventory applications in standard macOS application locations.
- Read application metadata, including bundle identifier, version, size, location, signing identity when available, and last-use metadata when available.
- Associate application bundles with caches, preferences, logs, saved state, containers, launch items, and application support data.
- Display association confidence and the evidence used.
- Distinguish application-created service data from user-created documents and projects.
- Uninstall applications by moving the bundle and approved related files to the Trash.
- Detect remaining related files after the operation and show a verification result.
- Allow application reset by removing only approved settings and caches while keeping the application bundle.

### 4.3 Developer and AI Area

The main navigation contains one "Developer & AI" destination. Its primary content is an AI application list. Plugins and Skills are not separate top-level destinations.

Selecting an AI application opens four tabs:

1. Overview
2. Data & Storage
3. Plugins
4. Skills

Codex and Claude receive deep first-version adapters. ChatGPT, Ollama, OpenCode, and other recognized AI applications receive basic application and known-directory size reporting in the first version.

Common Xcode, Homebrew, npm, and Python caches are recognized as developer data. SpacePilot explains their source and regeneration cost. Destructive environment management, package upgrades, and Docker image lifecycle management are outside the first version.

### 4.4 Codex and Claude Data

For Codex and Claude, the scanner classifies known local assets without reading or storing their text content:

- Conversations and history
- Logs and diagnostics
- Caches and temporary data
- Configuration
- Plugin metadata and installation footprint
- Skill metadata and installation footprint

The index stores filesystem metadata and classification results, not conversation text, prompt text, log contents, tokens, credentials, or secrets.

### 4.5 Plugin Model

A Plugin is an installed parent package that can contribute capabilities such as Skills, Apps or Connectors, tool servers, assets, and references.

For each Plugin, SpacePilot displays:

- Name and version
- Installation source
- Owning AI application
- Disk footprint
- Included Skills and other discoverable components
- Dependencies when available
- Permission information when exposed through a supported management interface
- Whether the Plugin is user-installed, bundled, cached, or system-managed

SpacePilot does not directly edit Plugin caches. Management actions use an official Plugin management entry point when one is available. Otherwise the Plugin remains inspectable and locatable, with a user-facing handoff to the owning application. Removing a Plugin must operate on the parent package and preview all child capabilities that will be affected.

### 4.6 Skill Model

A Skill is a directory containing a `SKILL.md` entry point and optional scripts, examples, references, templates, or assets.

The first version recognizes these confirmed local scopes:

- Shared across compatible agents: `/Users/yurunhao/.agents/skills`
- Codex-specific: `/Users/yurunhao/.codex/skills`
- Claude-specific: `/Users/yurunhao/.claude/skills`
- Plugin-provided: Skill directories inside a Plugin installation
- System-managed: bundled system Skill directories

For every Skill, SpacePilot records:

- Declared name and description
- Actual path
- Disk footprint
- Scope and visible agents
- Parent Plugin, if any
- Installation source
- Content fingerprint for duplicate detection
- Same-name conflict or override risk
- Management status: standalone, parent-managed, or system read-only

Skills never move between shared, Codex, and Claude directories. A standalone user Skill may be moved to the Trash after an explicit preview. Plugin-provided and system-managed Skills cannot be directly removed; the user is directed to the parent Plugin or owning system.

Shared Skills appear inside every compatible AI application's Skills tab with a "Shared across agents" source label. The same asset is not duplicated in storage totals.

## 5. Information Architecture

The main window uses a native `NavigationSplitView` with a stable sidebar and detail workspace.

Sidebar destinations:

- Overview
- Storage
- Applications
- Developer & AI
- Cleanup History

Settings is presented through the standard macOS Settings scene rather than as a sidebar destination.

### 5.1 Overview

- Internal disk summary
- Safe reclaim estimate
- Scan freshness and coverage
- Highest-value recommendations
- Recently changed application and AI usage

### 5.2 Storage

- Category and directory breakdown
- Large items
- Old items
- Risk and regeneration filters
- Search and reveal-in-Finder actions

### 5.3 Applications

- Searchable application list
- Application size and last-use summary
- Selected application detail
- Related-file groups with confidence and risk
- Reset and uninstall actions

### 5.4 Developer & AI

- AI application list with total local footprint
- Selected application tabs: Overview, Data & Storage, Plugins, Skills
- Cross-application duplicates and shared assets are secondary comparison views, not top-level navigation

### 5.5 Cleanup History

- Timestamped cleanup transactions
- Planned versus completed items
- Freed bytes
- Skipped and failed items
- Trash or regeneration recovery guidance
- Post-action verification result

## 6. Visual and Interaction Direction

### 6.1 Visual Thesis

A calm, native macOS utility with strong typography, generous alignment, system materials, and one blue accent; dense enough to be useful but never presented as a mosaic of decorative dashboard cards.

### 6.2 Content Plan

- Sidebar establishes location and scope.
- Detail header states the selected subject, current footprint, and scan freshness.
- The main workspace presents one dominant table, outline, or breakdown for the current task.
- A lightweight inspector or bottom action area explains the selected item's path, source, risk, and action.
- Confirmation sheets contain only the affected items, impact explanation, and one primary action.

### 6.3 Interaction Thesis

- Scan results progressively settle into place without blocking the window.
- Selection changes use restrained native transitions between overview and detail.
- Cleanup progress emphasizes verified bytes released rather than decorative animation.

### 6.4 Interface Rules

- Use native sidebar selection and semantic system colors.
- Use one leading icon and no more than two text lines per sidebar row.
- Avoid custom opaque sidebar backgrounds.
- Avoid a grid of small summary cards when a single hierarchy or table communicates better.
- Use cards only when the whole region is an interactive object.
- Support pointer, keyboard navigation, search, contextual menus, and standard commands.
- Follow Light and Dark mode automatically.
- Minimum main window size is 1,000 by 680 points; default size is 1,180 by 760 points.

## 7. Technical Architecture

### 7.1 Scene and State Model

- `WindowGroup`: primary SpacePilot window.
- `Settings`: permissions, scan preferences, cleanup behavior, and diagnostics.
- App-wide `@Observable` `AppModel`: active scan, latest complete snapshot, services, and global status.
- Window-scoped selection: sidebar destination, selected application or AI application, selected asset, and inspector visibility.
- `@AppStorage`: user preferences.
- Scanners, stores, and cleanup services are injected through the SwiftUI environment and protocol boundaries.

### 7.2 Source Structure

```text
SpacePilot/
  App/
  Models/
  Views/
    Overview/
    Storage/
    Applications/
    DeveloperAI/
    History/
    Shared/
  Stores/
  Services/
    Scanning/
    Applications/
    AIAdapters/
    Plugins/
    Skills/
    Cleanup/
    Permissions/
  Persistence/
  Rules/
  Support/
SpacePilotTests/
  Fixtures/
```

Views do not perform filesystem operations. Each scanner has one purpose and returns value models through a documented protocol.

### 7.3 Scan Pipeline

The scan coordinator runs three stages:

1. Quick inventory: volume capacity, installed applications, known top-level categories, and the previous complete snapshot.
2. Targeted analysis: application associations, Codex and Claude adapters, Plugin and Skill indexing, and developer cache analyzers.
3. On-demand deep analysis: directory traversal for a user-selected category or application.

Scans are cancellable. Partial results are kept in a temporary session and never replace the latest complete snapshot. The coordinator limits concurrent filesystem traversal to prevent excessive I/O and UI stalls.

### 7.4 Scanner Interfaces

Core scanner families:

- `VolumeScanner`
- `LargeItemScanner`
- `ApplicationScanner`
- `ApplicationArtifactResolver`
- `AIApplicationAdapter`
- `PluginScanner`
- `SkillScanner`
- `DeveloperCacheScanner`

AI adapters declare recognized root signatures, asset classifiers, ownership rules, and supported management capabilities. File locations are maintained as versioned rule data where practical rather than being scattered through views or action code.

### 7.5 Local Index

SQLite stores metadata needed for fast, repeatable results:

- Canonical path and volume identity
- File resource identifier when available
- Allocated and logical size
- Modification and creation dates
- Item category and owner
- Association confidence and evidence
- Risk and regeneration classification
- Source scope and parent relationship
- Content fingerprint for small manifest-like files and Skill metadata
- Scan session and cleanup transaction identifiers

File contents, conversation text, log text, credentials, and secret values are excluded.

### 7.6 Core Models

- `ScanSnapshot`: one complete, immutable view of discovered state.
- `ScannedItem`: filesystem metadata and classification.
- `ApplicationRecord`: application bundle and associated artifacts.
- `ArtifactAssociation`: owner, evidence, confidence, and risk.
- `AIApplicationRecord`: AI application plus data, Plugins, and Skills.
- `PluginRecord`: parent package, source, components, dependencies, and management capability.
- `SkillRecord`: path, scope, visible agents, parent Plugin, fingerprint, and conflict status.
- `CleanupCandidate`: one proposed action with reason and recovery behavior.
- `CleanupPlan`: immutable user-reviewed collection of candidates.
- `CleanupTransaction`: actual outcomes and verification state.

### 7.7 Association Confidence

Application and AI data associations use explicit evidence:

- Exact bundle identifier match
- Declared application group or container identifier
- Known manifest ownership
- Exact supported path rule
- Signed helper or login-item relationship
- Strong name or vendor match in an expected directory

High-confidence candidates can be recommended. Medium-confidence candidates are shown but not preselected. Low-confidence items remain unclassified and are never included in cleanup suggestions.

## 8. Cleanup Safety Architecture

Scanning and cleanup use separate services and data flows.

Before execution, the cleanup service:

1. Builds an immutable plan from the selected snapshot.
2. Rejects protected system paths, volume roots, user home roots, and unresolved path targets.
3. Rechecks file identity, modification date, and ownership evidence.
4. Stops or skips any item that changed after the plan was shown.
5. Requires a user confirmation sheet with exact paths, sizes, risks, and effects.

Risk classes:

- Safe: recreatable caches and temporary files. May be preselected but still shown.
- Rebuildable: logs, downloaded models, derived data, and settings whose loss has a clear regeneration cost. Not preselected.
- Sensitive: conversations, projects, documents, and user content. Never part of one-click cleanup and always separately confirmed.
- Managed: Plugin-provided Skills, system components, and provider-owned packages. No direct file mutation.

Sensitive and rebuildable user-visible items are moved to the Trash. Cache APIs may remove explicitly recognized cache contents after confirmation. The operation records successes, skips, and failures, then runs a targeted rescan. A partial failure is never reported as total success.

## 9. Permissions and Privacy

- The app explains why Full Disk Access improves coverage and opens the relevant System Settings page.
- Without Full Disk Access, the app continues with a limited scan and shows a coverage warning.
- The app does not attempt to bypass Transparency, Consent, and Control protections.
- Security-scoped bookmarks are used only for user-selected paths when necessary.
- No analytics containing paths, application names, AI data, or cleanup contents leave the device.
- First-version telemetry is local diagnostic logging with an explicit export action.

## 10. Error Handling

- Permission denied: continue with partial coverage and label every affected category.
- Application running: pause uninstall and ask the user to quit the application.
- Unknown path or format: display as unknown and do not create a cleanup recommendation.
- Scan cancelled or interrupted: preserve the last complete snapshot and discard the incomplete replacement.
- File changed or disappeared: skip it, record the reason, and recalculate the result.
- Cleanup failure: stop the related batch when continued actions may depend on the failed item; preserve per-item outcomes.
- Database corruption: move the metadata index aside, rebuild it from disk, and retain cleanup history in a separate transaction store when recoverable.
- Rule incompatibility: disable the affected adapter, show a diagnostic state, and leave its files untouched.

## 11. Testing Strategy

### 11.1 Unit Tests

- Rule matching and association confidence
- Risk classification
- Skill scope detection and same-name conflict detection
- Plugin parent-child relationships
- Cleanup plan protected-path rejection
- Size aggregation without double-counting shared Skills
- Cancellation and snapshot replacement behavior

### 11.2 Fixture Tests

Use synthetic directory trees and test application bundles for Codex, Claude, Plugins, Skills, caches, logs, conversations, and user documents. Fixtures must include permission failures, symlinks, disappearing files, same-name Skills, parent-managed Skills, and files modified after plan creation.

### 11.3 Integration Tests

- Scan an isolated temporary home-like tree.
- Build and execute a cleanup plan only against disposable fixtures.
- Verify moved files, untouched protected files, transaction outcomes, and recalculated freed bytes.
- Verify limited-mode behavior without Full Disk Access.

### 11.4 Manual macOS Tests

- Light and Dark mode
- Keyboard navigation and VoiceOver labels
- Full Disk Access onboarding
- Large directory cancellation and responsiveness
- Running-application uninstall guard
- Trash recovery
- Signed Release archive and Gatekeeper assessment

No automated test may delete files outside a freshly created, explicitly validated temporary directory.

## 12. Acceptance Criteria

- The app builds and runs on an Apple Silicon Mac with macOS 15 or later.
- The main window returns a useful quick result before targeted scanning completes.
- Repeated scans of unchanged fixtures produce stable totals and relationships.
- Scan coverage and permission limitations are always visible.
- Every cleanup candidate has a path, source, risk, effect, and recovery explanation.
- Test application uninstalls remove only approved related fixtures and never remove user-document fixtures.
- Codex and Claude show Data & Storage, Plugins, and Skills under the selected AI application.
- Shared Skills are visible to compatible applications without being double-counted.
- Codex-specific, Claude-specific, Plugin-provided, and system-managed Skills show their true source.
- Skills never move between scope directories.
- Plugin caches and managed Skills are not directly mutated.
- Cleanup history distinguishes success, skip, failure, and post-action verification.
- The interface remains responsive during large scans and supports cancellation.
- The UI follows a simple native hierarchy with no decorative dashboard-card mosaic.

## 13. Explicit Non-Goals

- Intel Mac support
- macOS 14 and earlier
- External, network, and cloud volume scanning
- Duplicate-photo or similar-image detection
- Media compression
- Cloud AI analysis
- User accounts and synchronization
- Background unattended cleanup
- Permanent deletion of user content
- Cross-agent Skill movement
- Direct mutation of Plugin caches or system-managed assets
- A Plugin or Skill marketplace
- Package upgrades or dependency environment repair
- Docker image, container, or volume lifecycle management

## 14. Delivery Sequence

1. Project scaffold, test harness, and native sidebar shell
2. Core models, SQLite index, and cancellable scan coordinator
3. Internal volume, large item, and application inventory scanners
4. Application association and safe uninstall planning
5. Cleanup transactions, Trash integration, and verification
6. Codex and Claude deep adapters
7. Plugin and Skill relationship indexing
8. Developer cache analyzers and basic other-AI reporting
9. Permissions, settings, history, accessibility, and performance polish
10. Release signing, notarization preparation, and acceptance audit
