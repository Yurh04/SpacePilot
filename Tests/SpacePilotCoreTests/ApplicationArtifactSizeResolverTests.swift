import Foundation
import XCTest
@testable import SpacePilotCore

final class ApplicationArtifactSizeResolverTests: XCTestCase {
    func testHardLinkedFilesAreCountedOnlyOnce() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "SpacePilot-HardLinks-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let original = root.appending(path: "original.bin")
        let hardLink = root.appending(path: "hard-link.bin")
        try Data(repeating: 0xA5, count: 16_384).write(to: original)
        try FileManager.default.linkItem(at: original, to: hardLink)
        let values = try original.resourceValues(forKeys: [
            .fileSizeKey,
            .totalFileAllocatedSizeKey
        ])

        let result = try await FileSystemApplicationArtifactSizeResolver()
            .sizes(of: root)

        XCTAssertEqual(result.logical, Int64(values.fileSize ?? 0))
        XCTAssertEqual(
            result.allocated,
            Int64(values.totalFileAllocatedSize ?? 0)
        )
    }
}
