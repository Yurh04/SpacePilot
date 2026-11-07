import XCTest
@testable import SpacePilotCore

final class DeveloperStorageScannerTests: XCTestCase {
    func testRecognizedDeveloperRootsAreSummarizedWithoutReadingContentBodies() async throws {
        let deviceID = "FCF5B243-403A-4857-AECB-4BC60E38A523"
        let tree = try TemporaryTree(files: [
            "Library/Developer/Xcode/DerivedData/App/Build/product": 50,
            "Library/Developer/CoreSimulator/Devices/\(deviceID)/data/data.db": 60,
            ".npm/_cacache/index": 20,
            "Library/Caches/Homebrew/download": 22,
            ".cache/pip/wheel": 24
        ])

        let result = try await DeveloperStorageScanner(
            processRunner: SimulatorFixtureRunner(deviceID: deviceID)
        ).scan(homeDirectory: tree.url)

        XCTAssertEqual(result.items.count, 6)
        XCTAssertTrue(result.items.allSatisfy { $0.category == .developer })
        XCTAssertEqual(result.items.first { $0.url.path.contains("DerivedData") }?.risk, .rebuildable)
        XCTAssertEqual(
            result.items.first {
                $0.developerStorageMetadata?.kind == .simulatorDevice
            }?.developerStorageMetadata?.name,
            "iPhone 17"
        )
        XCTAssertEqual(
            result.items.first {
                $0.developerStorageMetadata?.kind == .simulatorRuntime
            }?.allocatedSize,
            8_494_282_293
        )
        XCTAssertEqual(result.items.first { $0.url.path.contains("_cacache") }?.risk, .rebuildable)
        XCTAssertEqual(result.items.first { $0.url.path.contains("Homebrew") }?.risk, .rebuildable)
        XCTAssertEqual(result.items.first { $0.url.path.contains("pip") }?.risk, .rebuildable)
        XCTAssertTrue(result.items.filter { $0.risk == .rebuildable }.allSatisfy {
            $0.cleanupPolicyScope == .developerStorage
                && $0.cleanupPolicyRelativePath != nil
        })
    }

    func testValidDirectoryStatAvoidsRecursiveRecalculation() async throws {
        let tree = try TemporaryTree(files: [
            ".npm/_cacache/index": 20
        ])
        let root = tree.url.appending(
            path: ".npm/_cacache",
            directoryHint: .isDirectory
        )
        let scanner = DeveloperStorageScanner(
            directoryStats: FixedDirectoryStatProvider([
                root: (logical: 41_000, allocated: 52_000)
            ]),
            processRunner: EmptySimulatorRunner()
        )

        let result = try await scanner.scan(homeDirectory: tree.url)
        let item = try XCTUnwrap(result.items.first)

        XCTAssertEqual(item.logicalSize, 41_000)
        XCTAssertEqual(item.allocatedSize, 52_000)
    }

    func testRecognizesExpandedToolCachesButDoesNotOfferArchivesOrSimulatorDataForCleanup() async throws {
        let deviceID = "FCF5B243-403A-4857-AECB-4BC60E38A523"
        let tree = try TemporaryTree(files: [
            "Library/Developer/Xcode/iOS DeviceSupport/17/symbols": 31,
            ".m2/repository/org/example.jar": 32,
            "Library/Caches/ms-playwright/chromium/browser": 33,
            "Library/Developer/Xcode/Archives/App.xcarchive/app": 34,
            "Library/Developer/CoreSimulator/Devices/\(deviceID)/data/data.db": 35
        ])

        let result = try await DeveloperStorageScanner(
            processRunner: SimulatorFixtureRunner(deviceID: deviceID)
        ).scan(homeDirectory: tree.url)
        let cleanupItems = result.items.filter {
            $0.cleanupPolicyScope == .developerStorage
        }

        XCTAssertEqual(cleanupItems.count, 3)
        XCTAssertTrue(cleanupItems.allSatisfy { $0.risk == .rebuildable })
        XCTAssertFalse(cleanupItems.contains { $0.url.path.contains("Archives") })
        XCTAssertFalse(cleanupItems.contains { $0.url.path.contains("CoreSimulator") })
        XCTAssertEqual(
            result.items.filter {
                $0.developerStorageMetadata?.kind == .simulatorDevice
                    || $0.developerStorageMetadata?.kind == .simulatorRuntime
            }.count,
            2
        )
        XCTAssertTrue(result.items.filter {
            $0.developerStorageMetadata?.kind == .simulatorDevice
                || $0.developerStorageMetadata?.kind == .simulatorRuntime
        }.allSatisfy { $0.cleanupPolicyScope == nil && $0.risk == .sensitive })
    }
}

private struct EmptySimulatorRunner: CLIProcessRunning {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> CLIProcessOutput {
        CLIProcessOutput(
            standardOutput: Data("{}".utf8),
            standardError: Data(),
            terminationStatus: 0,
            didTimeout: false,
            outputTruncated: false
        )
    }
}

private struct SimulatorFixtureRunner: CLIProcessRunning {
    let deviceID: String

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> CLIProcessOutput {
        let json: String
        if arguments == ["simctl", "list", "devices", "-j"] {
            json = """
            {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-5":[{
              "name":"iPhone 17","udid":"\(deviceID)","state":"Shutdown",
              "isAvailable":true,"lastBootedAt":"2026-05-12T04:56:25Z"
            }]}}
            """
        } else {
            json = """
            {"runtime-id":{
              "build":"23F77","identifier":"runtime-id",
              "lastUsedAt":"2026-07-01T18:18:28Z",
              "runtimeBundlePath":"/Library/Developer/CoreSimulator/Volumes/iOS_23F77/Library/Developer/CoreSimulator/Profiles/Runtimes/iOS 26.5.simruntime",
              "runtimeIdentifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-5",
              "sizeBytes":8494282293,"state":"Ready","version":"26.5"
            }}
            """
        }
        return CLIProcessOutput(
            standardOutput: Data(json.utf8),
            standardError: Data(),
            terminationStatus: 0,
            didTimeout: false,
            outputTruncated: false
        )
    }
}
