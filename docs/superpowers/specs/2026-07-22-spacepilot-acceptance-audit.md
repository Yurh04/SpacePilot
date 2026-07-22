# SpacePilot Acceptance Audit

Date: 2026-07-22

## Product and platform

- Native Swift 6 and SwiftUI application with narrow AppKit use.
- Deployment target is macOS 15; build and packaging scripts reject non-arm64 Macs.
- The app is local-only and requires no account or network service.
- The current artifact is an ad-hoc Hardened Runtime `.app` and ZIP. Public direct distribution still requires the owner's Developer ID certificate and Apple notarization credentials.

## Storage and application management

- Quick inventory emits a displayable volume and application snapshot before targeted analysis.
- Targeted scanning is cancellable, records denied paths, avoids symlink traversal, and preserves the last complete SQLite snapshot on cancellation.
- Storage projections include internal volume use, classified user data, system/other space, largest items, items older than 180 days, and safe reclaim recommendations.
- Application inventory reads bundle metadata and associates only known service roots using explicit confidence evidence.
- Reset includes only high-confidence non-sensitive service data. Uninstall includes the bundle and high-confidence related data; user documents and medium-confidence associations are excluded.
- Cleanup plans reject broad, system, outside-volume, sensitive-without-confirmation, and provider-managed targets. Execution revalidates path, identity, recursive size, and modification date before moving to Trash.
- Cleanup history records success, partial failure, skips, failures, and bytes verified as removed from their original locations. Disk capacity is not claimed as physically freed while items remain in Trash.

## Developer and AI relationships

- Codex and Claude adapters classify conversations, logs, caches, configuration, Plugins, and Skills without indexing conversation or log bodies.
- ChatGPT, Ollama, and OpenCode use basic application and known-root footprint reporting.
- Xcode DerivedData and Archives, CoreSimulator, Homebrew, npm, Gradle, and pip roots are reported as developer storage with explicit risk.
- Plugins are parent packages. Their Skills are parent-managed and cannot enter cleanup plans; the UI hands management back to the owning application.
- Skills preserve shared, Codex-specific, Claude-specific, Plugin-provided, and system-managed scopes. No scope-movement action exists.
- Shared Skills and Plugin-contained Skills use identity sets and parent relationships to prevent double counting.

## Privacy, interface, and persistence

- SQLite stores versioned model metadata and cleanup history, not prompt, conversation, log, credential, token, or secret contents.
- Exported diagnostics contain counts and status metadata without filesystem paths or content bodies.
- The main UI uses a native sidebar with Overview, Storage, Applications, Developer & AI, and Cleanup History. Plugins and Skills remain nested under the selected AI application.
- Cleanup always uses an explicit confirmation sheet with exact paths, sizes, risk, effect, and Trash recovery guidance. Sensitive items require a separate acknowledgement.
- The Settings scene explains Full Disk Access, opens the official System Settings pane, and supports privacy-safe diagnostics export.
- Light and Dark mode were visually inspected with semantic system colors and the 1,000 x 680 minimum window size.

## Automated evidence

- Unit and fixture tests cover models, scanning, application association, AI rules, developer roots, Skill scopes/conflicts, Plugin traversal protection, SQLite recovery, cancellation, view projections, cleanup revalidation, directory cleanup, and partial failure.
- The end-to-end acceptance fixture covers two ordinary applications, ChatGPT, Codex, Claude, user-document exclusion, Plugin-managed Skills, shared and Agent-specific Skills, system Skills, conflict detection, developer cache reporting, and AI double-count prevention.
- `script/test_release.sh` runs all tests in parallel, builds Release, stages and launches the Release app, verifies its code structure/signature, creates a ZIP, and distinguishes expected ad-hoc Gatekeeper rejection from bundle failure.
