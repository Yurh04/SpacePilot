import Foundation
import XCTest
@testable import SpacePilotCore

final class StaleDiagnosticScannerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testFindsOnlyOldRegularFilesUnderKnownDiagnosticRoots() async throws {
        let now = self.now
        let fixture = try TemporaryTree(files: [
            "Library/Logs/old.log": 100,
            "Library/Logs/empty.log": 0,
            "Library/Logs/recent.log": 200,
            "Library/Logs/DiagnosticReports/app.ips": 300,
            ".npm/_logs/npm.log": 400,
            ".codex/logs/codex.log": 500,
            ".claude/debug/claude.txt": 600,
            "Documents/not-a-log.txt": 700
        ])
        try setModificationDate(now.addingTimeInterval(-31 * 24 * 60 * 60), for: [
            "Library/Logs/old.log",
            "Library/Logs/empty.log",
            "Library/Logs/DiagnosticReports/app.ips",
            ".npm/_logs/npm.log",
            ".codex/logs/codex.log",
            ".claude/debug/claude.txt",
            "Documents/not-a-log.txt"
        ], in: fixture)
        try setModificationDate(now.addingTimeInterval(-29 * 24 * 60 * 60), for: [
            "Library/Logs/recent.log"
        ], in: fixture)

        let result = try await StaleDiagnosticScanner(
            access: LocalFileSystemAccess(),
            now: { now }
        ).scan(homeDirectory: fixture.url)

        XCTAssertEqual(Set(result.items.map(\.url.lastPathComponent)), [
            "old.log", "app.ips", "npm.log", "codex.log", "claude.txt"
        ])
        XCTAssertTrue(result.items.allSatisfy { $0.category == .log })
        XCTAssertTrue(result.items.allSatisfy { $0.risk == .safe })
        XCTAssertTrue(result.items.allSatisfy {
            $0.explanation
                == StaleDiagnosticScanner<LocalFileSystemAccess>.explanation
        })
        XCTAssertTrue(result.coverage.isComplete)
    }

    func testSkipsSymbolicLinksAndDoesNotFollowLinkedDirectories() async throws {
        let now = self.now
        let fixture = try TemporaryTree(files: [
            "Library/Logs/actual/old.log": 100,
            "outside/other.log": 200
        ])
        let oldDate = now.addingTimeInterval(-31 * 24 * 60 * 60)
        try setModificationDate(oldDate, for: [
            "Library/Logs/actual/old.log",
            "outside/other.log"
        ], in: fixture)
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appending(path: "Library/Logs/linked"),
            withDestinationURL: fixture.url.appending(path: "outside")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.url.appending(path: "Library/Logs/linked.log"),
            withDestinationURL: fixture.url.appending(path: "outside/other.log")
        )

        let result = try await StaleDiagnosticScanner(
            access: LocalFileSystemAccess(),
            now: { now }
        ).scan(homeDirectory: fixture.url)

        XCTAssertEqual(result.items.map(\.url.lastPathComponent), ["old.log"])
    }

    func testReportsUnreadableKnownRootAndIgnoresMissingRoots() async throws {
        let now = self.now
        let fixture = try TemporaryTree(files: ["Library/Logs/old.log": 100])
        let logs = fixture.url.appending(path: "Library/Logs", directoryHint: .isDirectory)

        let result = try await StaleDiagnosticScanner(
            access: FixtureFileSystemAccess(unreadable: [logs]),
            now: { now }
        ).scan(homeDirectory: fixture.url)

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(result.coverage.deniedPaths, [logs.standardizedFileURL])
        XCTAssertFalse(result.coverage.isComplete)
    }

    private func setModificationDate(
        _ date: Date,
        for relativePaths: [String],
        in fixture: TemporaryTree
    ) throws {
        for relativePath in relativePaths {
            try FileManager.default.setAttributes(
                [.modificationDate: date],
                ofItemAtPath: fixture.url.appending(path: relativePath).path
            )
        }
    }
}
