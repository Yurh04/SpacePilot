import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

@MainActor
final class ProjectionPublicationTests: XCTestCase {
    func testApplyingNewSnapshotKeepsExistingProjectionUntilReplacementPublishes()
        async throws
    {
        let model = AppModel(
            runtime: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { _, _ in [] }
        let first = Self.snapshot(applicationName: "First")
        await model.applySnapshotForTesting(first)
        _ = try await projection(for: first.id, in: model)

        let second = Self.snapshot(applicationName: "Second")
        model.startForTesting(second)

        XCTAssertEqual(model.projection?.snapshotID, first.id)
        XCTAssertEqual(
            model.projection?.applications.applications.first?.application.name,
            "First"
        )

        let replacement = try await projection(for: second.id, in: model)
        XCTAssertEqual(
            replacement.applications.applications.first?.application.name,
            "Second"
        )
    }

    private func projection(
        for snapshotID: UUID,
        in model: AppModel
    ) async throws -> AppSnapshotProjection {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if let projection = model.projection,
               projection.snapshotID == snapshotID {
                return projection
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw ProjectionWaitError.timedOut(snapshotID)
    }

    private static func snapshot(applicationName: String) -> ScanSnapshot {
        ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [
                ApplicationRecord(
                    name: applicationName,
                    bundleIdentifier: "com.example.\(applicationName)",
                    version: "1",
                    url: URL(
                        fileURLWithPath: "/Applications/\(applicationName).app"
                    ),
                    executableURL: nil,
                    allocatedSize: 1
                )
            ],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
    }
}

private enum ProjectionWaitError: Error {
    case timedOut(UUID)
}
