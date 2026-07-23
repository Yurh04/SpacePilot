import Foundation
import XCTest
@testable import SpacePilotCore

final class ScanCoordinatorTests: XCTestCase {
    func testQuickInventoryArrivesBeforeTargetedCompletion() async throws {
        let coordinator = ScanCoordinator.fixture()
        var stages: [ScanStage] = []

        for try await event in coordinator.scan() {
            stages.append(event.stage)
        }

        XCTAssertEqual(stages.first, .quickInventory)
        XCTAssertEqual(stages.last, .completed)
    }

    func testQuickInventoryCanCarryDisplayablePartialSnapshot() async throws {
        let quick = ScanSnapshot.fixture()
        let coordinator = ScanCoordinator(operation: { emit in
            emit(ScanEvent(stage: .quickInventory, progress: 0.2, message: "Quick", snapshot: quick))
            emit(ScanEvent(stage: .completed, progress: 1, message: "Done", snapshot: quick))
            return quick
        })

        var firstSnapshot: ScanSnapshot?
        for try await event in coordinator.scan() where event.stage == .quickInventory {
            firstSnapshot = event.snapshot
        }

        XCTAssertEqual(firstSnapshot?.id, quick.id)
    }

    func testCancelledScanDoesNotReplaceLatestSnapshot() async throws {
        let previous = ScanSnapshot.fixture()
        let store = InMemorySnapshotStore(latest: previous)
        let coordinator = ScanCoordinator.fixture(store: store, suspendDuring: .targetedAnalysis)
        let task = Task { try await coordinator.collectScan() }
        try await Task.sleep(for: .milliseconds(20))

        task.cancel()
        _ = try? await task.value

        let saveCount = await store.saveCount
        let latestID = await store.latest?.id
        XCTAssertEqual(saveCount, 0)
        XCTAssertEqual(latestID, previous.id)
    }

    func testPermissionStatusNeverClaimsFullWhenPathsWereDenied() {
        let denied = [URL(fileURLWithPath: "/Users/test/Library/Mail")]
        XCTAssertEqual(PermissionService().coverageStatus(deniedPaths: denied), .limited(deniedPaths: denied))
    }

    func testSnapshotKeepsOneSharedItemWithAssociationsForBothApplications() async throws {
        let home = try TemporaryTree(files: [
            "Library/Group Containers/TEAM.shared/token.db": 64,
            "Library/Group Containers/TEAM.shared/.hidden-token.db": 17,
            "Library/Application Support/com.openai.chat/state.db": 32,
            "Library/Application Support/com.openai.chat/.hidden-state.db": 19
        ])
        let applicationsDirectory = home.url.appending(
            path: "Applications",
            directoryHint: .isDirectory
        )
        let first = try TestAppBuilder.make(
            in: applicationsDirectory,
            name: "First",
            bundleID: "com.example.first",
            version: "1.0",
            executableBytes: 16
        )
        let second = try TestAppBuilder.make(
            in: applicationsDirectory,
            name: "Second",
            bundleID: "com.example.second",
            version: "1.0",
            executableBytes: 16
        )
        let chatGPT = try TestAppBuilder.make(
            in: applicationsDirectory,
            name: "ChatGPT",
            bundleID: "com.openai.chat",
            version: "1.0",
            executableBytes: 16
        )
        _ = [first, second, chatGPT]
        let identityReader = SharedGroupIdentityReader(
            bundleIdentifiers: ["com.example.first", "com.example.second"]
        )
        let store = InMemorySnapshotStore()
        let coordinator = ScanCoordinator(
            homeDirectory: home.url,
            store: store,
            identityReader: identityReader
        )

        let snapshot = try await coordinator.collectScan()

        let sharedPath = home.url.appending(
            path: "Library/Group Containers/TEAM.shared"
        ).standardizedFileURL.path
        let sharedItems = snapshot.items.filter {
            $0.url.standardizedFileURL.path == sharedPath
        }
        let applications = snapshot.applications.filter {
            ["com.example.first", "com.example.second"].contains(
                $0.bundleIdentifier
            )
        }
        let associations = applications.flatMap(\.associations).filter {
            $0.itemID == sharedItems.first?.id
        }

        XCTAssertEqual(sharedItems.count, 1)
        XCTAssertNil(sharedItems.first?.ownerID)
        XCTAssertEqual(applications.count, 2)
        XCTAssertEqual(associations.count, 2)
        XCTAssertTrue(
            associations.allSatisfy { $0.ownership == .shared }
        )
        XCTAssertEqual(
            identityReader.readApplicationIDs,
            Set(snapshot.applications.map(\.id))
        )
        let snapshotItemIDs = Set(snapshot.items.map(\.id))
        XCTAssertTrue(
            snapshot.applications
                .flatMap(\.associations)
                .allSatisfy { snapshotItemIDs.contains($0.itemID) }
        )
        let chatGPTApplication = try XCTUnwrap(
            snapshot.applications.first {
                $0.bundleIdentifier == "com.openai.chat"
            }
        )
        let chatGPTPath = home.url.appending(
            path: "Library/Application Support/com.openai.chat"
        ).standardizedFileURL.path
        let chatGPTItem = try XCTUnwrap(
            snapshot.items.first {
                $0.url.standardizedFileURL.path == chatGPTPath
            }
        )
        XCTAssertEqual(chatGPTItem.ownerID, chatGPTApplication.id)
        XCTAssertEqual(
            chatGPTApplication.associations.first {
                $0.itemID == chatGPTItem.id
            }?.ownership,
            .owned
        )
        for aggregatePath in [sharedPath, chatGPTPath] {
            XCTAssertEqual(
                snapshot.items.filter {
                    let path = $0.url.standardizedFileURL.path
                    return path == aggregatePath
                        || path.hasPrefix(aggregatePath + "/")
                }.count,
                1
            )
        }

        let aggregateBytes = try XCTUnwrap(sharedItems.first).allocatedSize
            + chatGPTItem.allocatedSize
        let expectedAggregateBytes = try [
            "Library/Group Containers/TEAM.shared/token.db",
            "Library/Group Containers/TEAM.shared/.hidden-token.db",
            "Library/Application Support/com.openai.chat/state.db",
            "Library/Application Support/com.openai.chat/.hidden-state.db"
        ].reduce(Int64(0)) { total, relativePath in
            let values = try home.url.appending(
                path: relativePath
            ).resourceValues(forKeys: [.totalFileAllocatedSizeKey])
            return total + Int64(values.totalFileAllocatedSize ?? 0)
        }
        XCTAssertEqual(
            try XCTUnwrap(sharedItems.first).logicalSize,
            81
        )
        XCTAssertEqual(chatGPTItem.logicalSize, 51)
        XCTAssertEqual(aggregateBytes, expectedAggregateBytes)
        let applicationBytes = snapshot.applications.reduce(Int64(0)) {
            $0 + $1.allocatedSize
        }
        let overview = OverviewProjection(snapshot: snapshot)
        let storage = StorageProjection(snapshot: snapshot)
        XCTAssertEqual(
            overview.analyzedBytes,
            applicationBytes + aggregateBytes
        )
        XCTAssertEqual(
            storage.categories.first {
                $0.category == .application
            }?.allocatedSize,
            aggregateBytes
        )
        XCTAssertNil(
            storage.categories.first { $0.category == .personal }
        )
        XCTAssertTrue(
            snapshot.aiApplications
                .flatMap(\.itemIDs)
                .allSatisfy { snapshotItemIDs.contains($0) }
        )
    }
}

private final class SharedGroupIdentityReader:
    ApplicationIdentityReading,
    @unchecked Sendable
{
    private let bundleIdentifiers: Set<String>
    private let lock = NSLock()
    private var applicationIDs: Set<UUID> = []

    init(bundleIdentifiers: Set<String>) {
        self.bundleIdentifiers = bundleIdentifiers
    }

    var readApplicationIDs: Set<UUID> {
        lock.lock()
        defer { lock.unlock() }
        return applicationIDs
    }

    func read(application: ApplicationRecord) throws -> ApplicationIdentity {
        lock.lock()
        applicationIDs.insert(application.id)
        lock.unlock()

        return ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: application.bundleIdentifier,
            componentBundleIdentifiers: [],
            teamIdentifier: "TEAM",
            applicationGroups: bundleIdentifiers.contains(
                application.bundleIdentifier ?? ""
            ) ? ["TEAM.shared"] : []
        )
    }
}
