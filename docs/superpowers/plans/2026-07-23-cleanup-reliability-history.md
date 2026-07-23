# Cleanup Reliability and Explainable History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow explicitly selected live cache directories to be moved safely while preserving strict file identity checks and recording actionable cleanup history.

**Architecture:** Introduce one filesystem identity reader used by cleanup planning and execution. Planning refreshes the selected filesystem objects immediately before execution; execution validates regular files strictly and directories by stable root identity, then persists immutable source context on every outcome.

**Tech Stack:** Swift 6, Foundation URL resource values, Swift Testing through XCTest, Codable JSON persisted in SQLite.

## Global Constraints

- Minimum OS is macOS 15 and the build supports Apple Silicon only.
- Cleanup remains local, explicitly selected, and reversible through the Trash.
- `PathSafetyPolicy` validates every source before it can reach the mover.
- Existing cleanup-history JSON must continue decoding.
- Failed or skipped items never count toward verified reclaimed bytes.

---

### Task 1: Capture fresh cleanup identities

**Files:**
- Create: `Sources/SpacePilotCore/Cleanup/CleanupCandidateRefresher.swift`
- Modify: `Sources/SpacePilotCore/Models/CleanupModels.swift`
- Modify: `Sources/SpacePilotCore/Cleanup/CleanupPlanner.swift`
- Test: `Tests/SpacePilotCoreTests/CleanupPlannerTests.swift`

**Interfaces:**
- Consumes: `PathSafetyPolicy.validate(_:)` and selected `ScannedItem` values.
- Produces: `CleanupItemKind`, `CleanupCandidate.itemKind`, and `CleanupCandidateRefresher.refresh(item:policy:)`.

- [ ] **Step 1: Write failing planner tests**

Add tests proving planning uses current filesystem metadata rather than stale
scan size and captures whether the target is a file or directory:

```swift
func testPlannerRefreshesStaleDirectoryMetadata() throws {
    let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
    let directory = tree.url.appending(path: "Library/Caches/live")
    let stale = ScannedItem(
        url: directory,
        logicalSize: 1,
        allocatedSize: 1,
        category: .cache,
        risk: .safe,
        explanation: "Live cache"
    )
    try Data(repeating: 1, count: 4_096).write(to: directory.appending(path: "new.bin"))

    let plan = try CleanupPlanner(policy: .init(
        homeDirectory: tree.url,
        allowedVolumeRoot: tree.url
    )).makePlan(
        snapshotID: UUID(),
        items: [stale],
        selectedIDs: [stale.id],
        separatelyConfirmedSensitiveIDs: []
    )

    XCTAssertEqual(plan.candidates.first?.itemKind, .directory)
    XCTAssertGreaterThan(plan.candidates.first?.allocatedSize ?? 0, stale.allocatedSize)
}
```

- [ ] **Step 2: Run the focused test and verify failure**

Run:

```bash
swift test --filter CleanupPlannerTests.testPlannerRefreshesStaleDirectoryMetadata
```

Expected: compilation fails because `CleanupItemKind` and `itemKind` do not
exist.

- [ ] **Step 3: Add the identity model and refresher**

Define the item kind and a single metadata capture path:

```swift
public enum CleanupItemKind: String, Codable, Sendable {
    case regularFile
    case directory
}

public struct CleanupCandidateRefresher: Sendable {
    public init() {}

    public func refresh(item: ScannedItem, policy: PathSafetyPolicy) throws -> CleanupCandidate {
        let url = try policy.validate(item.url)
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ])
        let kind: CleanupItemKind
        let size: Int64
        if values.isDirectory == true {
            kind = .directory
            size = recursiveAllocatedSize(of: url)
        } else if values.isRegularFile == true {
            kind = .regularFile
            size = Int64(values.totalFileAllocatedSize ?? 0)
        } else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard let resourceIdentifier = values.fileResourceIdentifier else {
            throw CocoaError(.fileReadUnknown)
        }
        return CleanupCandidate(
            itemID: item.id,
            url: url,
            allocatedSize: size,
            risk: item.risk,
            itemKind: kind,
            expectedResourceIdentifier: String(describing: resourceIdentifier),
            expectedModificationDate: values.contentModificationDate,
            explanation: item.explanation
        )
    }
}
```

Move recursive allocated-size calculation into this file and have
`CleanupPlanner` call the refresher after risk and sensitive-confirmation
validation.

- [ ] **Step 4: Run planner tests**

Run:

```bash
swift test --filter CleanupPlannerTests
```

Expected: all `CleanupPlannerTests` pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Cleanup/CleanupCandidateRefresher.swift Sources/SpacePilotCore/Models/CleanupModels.swift Sources/SpacePilotCore/Cleanup/CleanupPlanner.swift Tests/SpacePilotCoreTests/CleanupPlannerTests.swift
git commit -m "fix: refresh cleanup identities before execution"
```

---

### Task 2: Validate live directories without weakening file checks

**Files:**
- Modify: `Sources/SpacePilotCore/Cleanup/CleanupExecutor.swift`
- Test: `Tests/SpacePilotCoreTests/CleanupExecutorTests.swift`

**Interfaces:**
- Consumes: refreshed `CleanupCandidate.itemKind` and identity metadata from Task 1.
- Produces: type-aware `identityStillMatches(_:at:)`.

- [ ] **Step 1: Write failing executor tests**

Add one test for allowed directory content churn and one for rejected directory
replacement:

```swift
func testDirectoryWithChangedContentsStillMovesWhenRootIdentityMatches() async throws {
    let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
    let directory = tree.url.appending(path: "Library/Caches/live")
    let policy = PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url)
    let item = ScannedItem(
        url: directory,
        logicalSize: 16,
        allocatedSize: 16,
        category: .cache,
        risk: .safe,
        explanation: "Live cache"
    )
    let candidate = try CleanupCandidateRefresher().refresh(item: item, policy: policy)
    try Data(repeating: 2, count: 512).write(to: directory.appending(path: "new.bin"))
    let mover = try FixtureTrashMover(destination: tree.url.appending(path: "FixtureTrash"))

    let result = try await CleanupExecutor(policy: policy, mover: mover)
        .execute(plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate]))

    XCTAssertEqual(result.outcomes.first?.status, .movedToTrash)
}

func testReplacedDirectoryIsSkipped() async throws {
    let tree = try TemporaryTree(files: ["Library/Caches/live/old.bin": 16])
    let directory = tree.url.appending(path: "Library/Caches/live")
    let policy = PathSafetyPolicy(homeDirectory: tree.url, allowedVolumeRoot: tree.url)
    let item = ScannedItem(
        url: directory,
        logicalSize: 16,
        allocatedSize: 16,
        category: .cache,
        risk: .safe,
        explanation: "Live cache"
    )
    let candidate = try CleanupCandidateRefresher().refresh(item: item, policy: policy)
    try FileManager.default.removeItem(at: directory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let result = try await CleanupExecutor(policy: policy, mover: RecordingTrashMover())
        .execute(plan: CleanupPlan(snapshotID: UUID(), candidates: [candidate]))

    XCTAssertEqual(result.outcomes.first?.status, .skippedChanged)
}
```

- [ ] **Step 2: Run focused tests and verify the first fails**

Run:

```bash
swift test --filter CleanupExecutorTests
```

Expected: the live-directory test reports `.skippedChanged`.

- [ ] **Step 3: Implement type-aware identity validation**

Replace recursive directory size and modification-date equality with:

```swift
private func identityStillMatches(_ candidate: CleanupCandidate, at url: URL) -> Bool {
    guard let values = try? url.resourceValues(forKeys: [
        .isDirectoryKey,
        .isRegularFileKey,
        .totalFileAllocatedSizeKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey
    ]) else { return false }
    let actualIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
    if let expected = candidate.expectedResourceIdentifier,
       expected != actualIdentifier { return false }

    switch candidate.itemKind {
    case .directory:
        return values.isDirectory == true
    case .regularFile:
        guard values.isRegularFile == true,
              candidate.allocatedSize == Int64(values.totalFileAllocatedSize ?? 0)
        else { return false }
        if let expected = candidate.expectedModificationDate {
            guard let actual = values.contentModificationDate,
                  abs(actual.timeIntervalSince(expected)) < 0.001
            else { return false }
        }
        return true
    }
}
```

Keep `policy.validate(candidate.url)` immediately before this check.

- [ ] **Step 4: Run cleanup tests**

Run:

```bash
swift test --filter CleanupExecutorTests
```

Expected: all cleanup executor tests pass, including strict changed-file,
replaced-directory, and live-directory cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/SpacePilotCore/Cleanup/CleanupExecutor.swift Tests/SpacePilotCoreTests/CleanupExecutorTests.swift
git commit -m "fix: allow safe live directory cleanup"
```

---

### Task 3: Persist explainable cleanup outcomes

**Files:**
- Modify: `Sources/SpacePilotCore/Models/CleanupModels.swift`
- Modify: `Sources/SpacePilotCore/Cleanup/CleanupExecutor.swift`
- Modify: `Sources/SpacePilot/Views/History/CleanupHistoryView.swift`
- Modify: `Sources/SpacePilot/Localization/L10n.swift`
- Modify: `Sources/SpacePilot/Resources/en.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/zh-Hans.lproj/Localizable.strings`
- Modify: `Sources/SpacePilot/Resources/Localizable.xcstrings`
- Test: `Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift`
- Test: `Tests/SpacePilotTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: cleanup candidates and statuses from Tasks 1–2.
- Produces: `CleanupOutcomeReason` plus optional `CleanupOutcome.sourceURL`, `sourceAllocatedSize`, and `sourceExplanation` fields compatible with old JSON.

- [ ] **Step 1: Write backward-compatibility and round-trip tests**

Add:

```swift
func testCleanupOutcomeDecodesLegacyPayloadWithoutSourceContext() throws {
    let json = """
    {"id":"00000000-0000-0000-0000-000000000001",
     "candidateID":"00000000-0000-0000-0000-000000000002",
     "status":"skippedChanged",
     "resultingURL":null,
     "message":"File changed after the scan and was not moved"}
    """.data(using: .utf8)!
    let outcome = try JSONDecoder().decode(CleanupOutcome.self, from: json)
    XCTAssertNil(outcome.sourceURL)
    XCTAssertNil(outcome.sourceAllocatedSize)
    XCTAssertNil(outcome.reason)
}
```

Extend the store round-trip fixture with a source URL and assert it survives.

- [ ] **Step 2: Run tests and verify source properties are missing**

Run:

```bash
swift test --filter SQLiteIndexStoreTests
```

Expected: compilation fails on the new source properties.

- [ ] **Step 3: Add optional source context and populate every outcome**

Extend `CleanupOutcome` without custom migration:

```swift
public enum CleanupOutcomeReason: String, Codable, Sendable {
    case moved
    case changedIdentity
    case missingSource
    case protectedPath
    case permissionDenied
    case moveFailed
}

public let reason: CleanupOutcomeReason?
public let sourceURL: URL?
public let sourceAllocatedSize: Int64?
public let sourceExplanation: String?
```

Give new initializer properties defaults of `nil`. In `CleanupExecutor`,
distinguish a missing path before identity comparison, map path-policy failures
to `.protectedPath`, and map `CocoaError.fileWriteNoPermission` to
`.permissionDenied`. Construct outcomes through a helper so all branches
capture the candidate:

```swift
private func outcome(
    for candidate: CleanupCandidate,
    status: CleanupOutcomeStatus,
    reason: CleanupOutcomeReason,
    resultingURL: URL? = nil,
    message: String
) -> CleanupOutcome {
    CleanupOutcome(
        candidateID: candidate.id,
        status: status,
        resultingURL: resultingURL,
        message: message,
        reason: reason,
        sourceURL: candidate.url,
        sourceAllocatedSize: candidate.allocatedSize,
        sourceExplanation: candidate.explanation
    )
}
```

- [ ] **Step 4: Show source details and localize failure categories**

Render an outcome with its file name, parent path, size, localized status, and
localized message. Old outcomes fall back to the existing message-only row:

```swift
if let sourceURL = outcome.sourceURL {
    VStack(alignment: .leading, spacing: 2) {
        Text(sourceURL.lastPathComponent)
        Text(sourceURL.deletingLastPathComponent().path(percentEncoded: false))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
    Spacer()
    if let bytes = outcome.sourceAllocatedSize {
        Text(ByteCount.string(bytes)).monospacedDigit()
    }
    Text(verbatim: L10n.name(for: outcome.status))
} else {
    LabeledContent(
        L10n.cleanupOutcomeMessage(outcome.message, status: outcome.status),
        value: L10n.name(for: outcome.status)
    )
}
```

Add synchronized English and Simplified Chinese strings for source path,
changed identity, missing source, protected path, permission failure, and
generic move failure.

- [ ] **Step 5: Run persistence and localization tests**

Run:

```bash
swift test --filter SQLiteIndexStoreTests
swift test --filter LocalizationTests
```

Expected: both suites pass and localization keys are exactly synchronized.

- [ ] **Step 6: Commit**

```bash
git add Sources/SpacePilotCore/Models/CleanupModels.swift Sources/SpacePilotCore/Cleanup/CleanupExecutor.swift Sources/SpacePilot/Views/History/CleanupHistoryView.swift Sources/SpacePilot/Localization/L10n.swift Sources/SpacePilot/Resources Tests/SpacePilotCoreTests/SQLiteIndexStoreTests.swift Tests/SpacePilotTests/LocalizationTests.swift
git commit -m "feat: explain cleanup outcomes with source paths"
```
