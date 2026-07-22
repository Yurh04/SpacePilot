import Foundation

public struct DeveloperStorageScanResult: Sendable {
    public let items: [ScannedItem]
}

public struct DeveloperStorageScanner: Sendable {
    private struct Rule: Sendable {
        let relativePath: String
        let risk: RiskLevel
        let explanation: String
    }

    private let rules: [Rule] = [
        .init(relativePath: "Library/Developer/Xcode/DerivedData", risk: .rebuildable, explanation: "Xcode build products and indexes"),
        .init(relativePath: "Library/Developer/Xcode/Archives", risk: .sensitive, explanation: "Xcode release archives"),
        .init(relativePath: "Library/Developer/CoreSimulator", risk: .sensitive, explanation: "Simulator runtimes and device data"),
        .init(relativePath: ".npm/_cacache", risk: .safe, explanation: "npm download cache"),
        .init(relativePath: ".gradle/caches", risk: .safe, explanation: "Gradle dependency cache"),
        .init(relativePath: "Library/Caches/Homebrew", risk: .safe, explanation: "Homebrew download cache"),
        .init(relativePath: "Library/Caches/pip", risk: .safe, explanation: "Python pip download cache"),
        .init(relativePath: ".cache/pip", risk: .safe, explanation: "Python pip download cache")
    ]

    public init() {}

    public func scan(homeDirectory: URL) async throws -> DeveloperStorageScanResult {
        var items: [ScannedItem] = []
        for rule in rules {
            try Task.checkCancellation()
            let root = homeDirectory.appending(path: rule.relativePath, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let sizes = directorySizes(root)
            items.append(ScannedItem(
                url: root,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                category: .developer,
                risk: rule.risk,
                explanation: rule.explanation
            ))
        }
        return DeveloperStorageScanResult(items: items.sorted { $0.allocatedSize > $1.allocatedSize })
    }

    private func directorySizes(_ root: URL) -> (logical: Int64, allocated: Int64) {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return (0, 0) }
        var logical: Int64 = 0
        var allocated: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            logical += Int64(values.fileSize ?? 0)
            allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return (logical, allocated)
    }
}
