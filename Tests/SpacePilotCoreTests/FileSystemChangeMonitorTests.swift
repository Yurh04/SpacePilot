import CoreServices
import Foundation
import XCTest
@testable import SpacePilotCore

final class FileSystemChangeMonitorTests: XCTestCase {
    func testReducerCollapsesDescendantsButKeepsSiblings() {
        let root = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        let paths = ChangedPathReducer.reduce([
            root.appending(path: ".codex/sessions/one.jsonl"),
            root.appending(path: ".codex"),
            root.appending(path: ".codex/logs/log.txt"),
            root.appending(path: ".claude/settings.json"),
            URL(fileURLWithPath: "/tmp/outside")
        ], within: root)

        XCTAssertEqual(
            Set(paths.map(\.path)),
            Set([
                "/Users/test/.codex",
                "/Users/test/.claude/settings.json"
            ])
        )
    }

    func testReducerRetainsAllDistinctPathsInMaximumBatch() {
        let root = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let paths = (0..<FileSystemChangeMonitor.maximumChangedPathsPerBatch)
            .map { index in
                root.appending(path: "Library/Caches/tool-\(index)/state.json")
            }

        let reduced = ChangedPathReducer.reduce(paths, within: root)

        XCTAssertEqual(reduced.count, paths.count)
        XCTAssertEqual(
            Set(reduced.map(\.path)),
            Set(paths.map(\.path))
        )
    }

    func testDroppedEventsRequireFullInvalidation() {
        XCTAssertTrue(FileSystemChangeMonitor.requiresFullInvalidation(
            FSEventStreamEventFlags(kFSEventStreamEventFlagKernelDropped)
        ))
        XCTAssertTrue(FileSystemChangeMonitor.requiresFullInvalidation(
            FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        ))
        XCTAssertFalse(FileSystemChangeMonitor.requiresFullInvalidation(
            FSEventStreamEventFlags(kFSEventStreamEventFlagItemModified)
        ))
    }

    func testReconcilerMergesBatchesAndKeepsNewestCursor() async {
        let root = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let recorder = ReconciledBatchRecorder()
        let reconciler = FileSystemChangeReconciler(
            root: root,
            debounceDuration: .seconds(30)
        ) {
            await recorder.record($0)
        }

        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [
                root.appending(path: ".codex/sessions/one.jsonl")
            ],
            lastEventID: 41,
            requiresFullInvalidation: false
        ))
        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [
                root.appending(path: ".codex"),
                root.appending(path: ".claude/settings.json")
            ],
            lastEventID: 43,
            requiresFullInvalidation: false
        ))
        await reconciler.flushPending()

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.lastEventID, 43)
        XCTAssertEqual(
            Set(batches.first?.changedPaths.map(\.path) ?? []),
            ["/Users/test/.codex", "/Users/test/.claude/settings.json"]
        )
        XCTAssertEqual(batches.first?.requiresFullInvalidation, false)
    }

    func testFullInvalidationDominatesPendingPaths() async {
        let root = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let recorder = ReconciledBatchRecorder()
        let reconciler = FileSystemChangeReconciler(
            root: root,
            debounceDuration: .seconds(30)
        ) {
            await recorder.record($0)
        }

        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [root.appending(path: ".codex/logs/log.txt")],
            lastEventID: 50,
            requiresFullInvalidation: false
        ))
        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [],
            lastEventID: 51,
            requiresFullInvalidation: true
        ))
        await reconciler.flushPending()

        let batch = await recorder.batches.first
        XCTAssertEqual(batch?.lastEventID, 51)
        XCTAssertEqual(batch?.changedPaths, [])
        XCTAssertEqual(batch?.requiresFullInvalidation, true)
    }

    func testReconcilerFlushesOnceAfterChangesBecomeQuiet() async throws {
        let root = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let recorder = ReconciledBatchRecorder()
        let reconciler = FileSystemChangeReconciler(
            root: root,
            debounceDuration: .milliseconds(20)
        ) {
            await recorder.record($0)
        }

        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [root.appending(path: ".codex/logs/one.log")],
            lastEventID: 60,
            requiresFullInvalidation: false
        ))
        try await Task.sleep(for: .milliseconds(10))
        await reconciler.submit(FileSystemChangeBatch(
            changedPaths: [root.appending(path: ".codex/logs/two.log")],
            lastEventID: 61,
            requiresFullInvalidation: false
        ))
        try await Task.sleep(for: .milliseconds(50))

        let batches = await recorder.batches
        XCTAssertEqual(batches.count, 1)
        XCTAssertEqual(batches.first?.lastEventID, 61)
        XCTAssertEqual(batches.first?.changedPaths.count, 2)
    }

    func testIncrementalRefreshPlannerSelectsSmallestUsefulScope() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)

        XCTAssertEqual(
            IncrementalRefreshPlanner.scope(
                for: FileSystemChangeBatch(
                    changedPaths: [
                        home.appending(path: ".codex/sessions/one.jsonl")
                    ],
                    lastEventID: 1,
                    requiresFullInvalidation: false
                ),
                homeDirectory: home
            ),
            .developerAI
        )
        XCTAssertEqual(
            IncrementalRefreshPlanner.scope(
                for: FileSystemChangeBatch(
                    changedPaths: [
                        home.appending(
                            path: "Library/Preferences/com.example.app.plist"
                        )
                    ],
                    lastEventID: 2,
                    requiresFullInvalidation: false
                ),
                homeDirectory: home
            ),
            .applications
        )
        XCTAssertNil(
            IncrementalRefreshPlanner.scope(
                for: FileSystemChangeBatch(
                    changedPaths: [
                        home.appending(path: "Documents/notes.txt")
                    ],
                    lastEventID: 3,
                    requiresFullInvalidation: false
                ),
                homeDirectory: home
            )
        )
    }
}

private actor ReconciledBatchRecorder {
    private(set) var batches: [FileSystemChangeBatch] = []

    func record(_ batch: FileSystemChangeBatch) {
        batches.append(batch)
    }
}
