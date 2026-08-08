import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

@MainActor
final class AIManagementDiscoveryTests: XCTestCase {
    func testPublishesDiscoveredRecordsForSnapshot() async {
        let records = [Self.record(name: "Codex")]
        let offMain = OffMainFlag()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in
            // Capture the thread synchronously in the worker body, before any
            // suspension, so the observation reflects where the worker runs.
            let isOffMain = currentThreadIsOffMain()
            await offMain.record(offMain: isOffMain)
            return records
        }
        await model.applySnapshotForTesting(Self.snapshot())
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["Codex"])
        XCTAssertFalse(model.isDiscoveringAITools)
        XCTAssertNil(model.aiDiscoveryError)
        let ranOffMain = await offMain.observedOffMain
        XCTAssertTrue(ranOffMain, "discovery worker must run off the MainActor")
    }

    func testStaleDiscoveryDoesNotOverwriteNewerSnapshot() async {
        // A slow first discovery for snapshot A must not overwrite the result of
        // a faster, newer discovery for snapshot B.
        let gate = AsyncGate()
        let slowRecords = [Self.record(name: "OldA")]
        let fastRecords = [Self.record(name: "NewB")]

        let model = AppModel(runtime: nil, homeDirectory: Self.home) { snapshot, _ in
            if snapshot.aiApplications.first?.name == "A" {
                await gate.wait()
                return slowRecords
            }
            return fastRecords
        }

        let snapshotA = Self.snapshot(aiName: "A")
        let snapshotB = Self.snapshot(aiName: "B")

        // Kick off A (blocked), then apply B which completes, then release A and
        // await A's own publication task before asserting B still wins.
        let staleTask = model.startForTesting(snapshotA)
        await model.applySnapshotForTesting(snapshotB)
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["NewB"])

        await gate.open()
        await staleTask?.value
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["NewB"])
    }

    func testUnchangedInputsDoNotRerunDiscovery() async {
        let counter = CallCounter()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in
            await counter.increment()
            return [Self.record(name: "Codex")]
        }
        let snapshot = Self.snapshot()
        // Same AI-relevant inputs across two applies (new snapshot id each time).
        await model.applySnapshotForTesting(Self.snapshotVariant(of: snapshot))
        await model.applySnapshotForTesting(Self.snapshotVariant(of: snapshot))
        let count = await counter.value
        XCTAssertEqual(count, 1)
    }

    func testForceRerunsDiscoveryEvenWhenInputsUnchanged() async {
        let counter = CallCounter()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in
            await counter.increment()
            return [Self.record(name: "Codex")]
        }
        await model.applySnapshotForTesting(Self.snapshot())
        await model.applySnapshotForTesting(Self.snapshot(), force: true)
        let count = await counter.value
        XCTAssertEqual(count, 2)
    }

    func testFailedFirstPassAllowsRetryForSameInputs() async {
        struct Boom: Error {}
        let counter = CallCounter()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in
            let attempt = await counter.incrementReturning()
            if attempt == 1 { throw Boom() }
            return [Self.record(name: "Codex")]
        }
        // First pass fails: same fingerprint but not marked successful.
        await model.applySnapshotForTesting(Self.snapshotVariant(of: Self.snapshot()))
        XCTAssertNotNil(model.aiDiscoveryError)
        XCTAssertTrue(model.aiManagementProjection.isEmpty)
        // Same AI inputs, non-forced: must retry because the first never succeeded.
        await model.applySnapshotForTesting(Self.snapshotVariant(of: Self.snapshot()))
        let count = await counter.value
        XCTAssertEqual(count, 2)
        XCTAssertNil(model.aiDiscoveryError)
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["Codex"])
    }

    func testCancelledFirstPassAllowsRetryWithoutError() async {
        let gate = AsyncGate()
        let counter = CallCounter()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in
            let attempt = await counter.incrementReturning()
            if attempt == 1 {
                await gate.wait()
                try Task.checkCancellation()
            }
            return [Self.record(name: "Codex")]
        }
        // Start a first pass and cancel it via cancelScan before it can publish.
        let firstTask = model.startForTesting(Self.snapshotVariant(of: Self.snapshot()))
        model.cancelScan()
        await gate.open()
        await firstTask?.value
        XCTAssertNil(model.aiDiscoveryError)
        XCTAssertTrue(model.aiManagementProjection.isEmpty)
        // Same AI inputs, non-forced: cancellation must not suppress the retry.
        await model.applySnapshotForTesting(Self.snapshotVariant(of: Self.snapshot()))
        let count = await counter.value
        XCTAssertEqual(count, 2)
        XCTAssertNil(model.aiDiscoveryError)
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["Codex"])
    }

    func testDiscoveryFailureSetsDiscoveryErrorNotScanError() async {
        struct Boom: Error {}
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { _, _ in throw Boom() }
        model.errorMessage = "scan-error"
        await model.applySnapshotForTesting(Self.snapshot())
        XCTAssertNotNil(model.aiDiscoveryError)
        XCTAssertEqual(model.errorMessage, "scan-error")
        XCTAssertTrue(model.aiManagementProjection.isEmpty)
        XCTAssertFalse(model.isDiscoveringAITools)
    }

    func testCancellationIsSilentAndKeepsExistingResults() async {
        let gate = AsyncGate()
        let model = AppModel(runtime: nil, homeDirectory: Self.home) { snapshot, _ in
            if snapshot.aiApplications.first?.name == "A" {
                await gate.wait()
                throw CancellationError()
            }
            return [Self.record(name: "NewB")]
        }
        let staleTask = model.startForTesting(Self.snapshot(aiName: "A"))
        await model.applySnapshotForTesting(Self.snapshot(aiName: "B"))
        await gate.open()
        await staleTask?.value
        XCTAssertEqual(model.aiManagementProjection.records.map(\.displayName), ["NewB"])
        XCTAssertNil(model.aiDiscoveryError)
    }

    // MARK: - Fixtures

    private static let home = URL(fileURLWithPath: "/Users/test")

    private nonisolated static func record(name: String) -> AIToolRecord {
        AIToolRecord(
            id: "application:\(name):/\(name)",
            kind: .application,
            displayName: name,
            owner: .tool(definitionID: name)
        )
    }

    private nonisolated static func snapshot(aiName: String = "Codex") -> ScanSnapshot {
        ScanSnapshot(
            completedAt: Date(timeIntervalSince1970: 0),
            volume: nil,
            items: [],
            applications: [],
            aiApplications: [
                AIApplicationRecord(
                    name: aiName,
                    bundleIdentifier: "com.example.\(aiName)",
                    applicationURL: URL(fileURLWithPath: "/Applications/\(aiName).app"),
                    rootURLs: [],
                    itemIDs: [],
                    pluginIDs: [],
                    skillIDs: [],
                    applicationAllocatedSize: 0,
                    supportLevel: .basic
                )
            ],
            plugins: [],
            skills: [],
            coverage: .complete
        )
    }

    /// Produces a snapshot with a fresh id but identical AI-relevant inputs.
    private static func snapshotVariant(of snapshot: ScanSnapshot) -> ScanSnapshot {
        ScanSnapshot(
            completedAt: Date(),
            volume: snapshot.volume,
            items: snapshot.items,
            applications: snapshot.applications,
            aiApplications: snapshot.aiApplications,
            plugins: snapshot.plugins,
            skills: snapshot.skills,
            coverage: snapshot.coverage
        )
    }
}

// MARK: - Async test helpers

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

private actor CallCounter {
    private(set) var value = 0
    func increment() { value += 1 }
    func incrementReturning() -> Int {
        value += 1
        return value
    }
}

/// Records whether the injected discovery closure ran off the MainActor, proving
/// the worker is not silently inheriting the model's actor.
private actor OffMainFlag {
    private(set) var observedOffMain = false
    func record(offMain: Bool) {
        if offMain { observedOffMain = true }
    }
}

/// Synchronous, non-isolated bridge to `Thread.isMainThread`, which is otherwise
/// unavailable directly from an async context.
private nonisolated func currentThreadIsOffMain() -> Bool {
    !Thread.isMainThread
}
