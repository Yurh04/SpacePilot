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

}
