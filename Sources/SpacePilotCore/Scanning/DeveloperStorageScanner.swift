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
        .init(relativePath: "Library/Developer/Xcode/iOS DeviceSupport", risk: .rebuildable, explanation: "Xcode iOS device support"),
        .init(relativePath: "Library/Developer/Xcode/watchOS DeviceSupport", risk: .rebuildable, explanation: "Xcode watchOS device support"),
        .init(relativePath: "Library/Developer/Xcode/tvOS DeviceSupport", risk: .rebuildable, explanation: "Xcode tvOS device support"),
        .init(relativePath: "Library/Developer/Xcode/visionOS DeviceSupport", risk: .rebuildable, explanation: "Xcode visionOS device support"),
        .init(relativePath: "Library/Developer/Xcode/xrOS DeviceSupport", risk: .rebuildable, explanation: "Xcode xrOS device support"),
        .init(relativePath: "Library/Developer/Xcode/DocumentationCache", risk: .rebuildable, explanation: "Xcode documentation cache"),
        .init(relativePath: "Library/Caches/com.apple.dt.Xcode", risk: .rebuildable, explanation: "Xcode cache"),
        .init(relativePath: ".npm/_cacache", risk: .rebuildable, explanation: "npm download cache"),
        .init(relativePath: ".npm/_npx", risk: .rebuildable, explanation: "npx package cache"),
        .init(relativePath: ".npm/_logs", risk: .rebuildable, explanation: "npm diagnostic logs"),
        .init(relativePath: "Library/pnpm/store", risk: .rebuildable, explanation: "pnpm package store"),
        .init(relativePath: ".local/share/pnpm/store", risk: .rebuildable, explanation: "pnpm package store"),
        .init(relativePath: "Library/Caches/Yarn", risk: .rebuildable, explanation: "Yarn package cache"),
        .init(relativePath: ".cache/yarn", risk: .rebuildable, explanation: "Yarn package cache"),
        .init(relativePath: ".gradle/caches", risk: .rebuildable, explanation: "Gradle dependency cache"),
        .init(relativePath: ".gradle/wrapper/dists", risk: .rebuildable, explanation: "Gradle wrapper distributions"),
        .init(relativePath: ".m2/repository", risk: .rebuildable, explanation: "Maven dependency cache"),
        .init(relativePath: "Library/Caches/Homebrew", risk: .rebuildable, explanation: "Homebrew download cache"),
        .init(relativePath: "Library/Caches/pip", risk: .rebuildable, explanation: "Python pip download cache"),
        .init(relativePath: ".cache/pip", risk: .rebuildable, explanation: "Python pip download cache"),
        .init(relativePath: "Library/Caches/ms-playwright", risk: .rebuildable, explanation: "Playwright browsers"),
        .init(relativePath: ".cache/ms-playwright", risk: .rebuildable, explanation: "Playwright browsers"),
        .init(relativePath: "Library/Caches/puppeteer", risk: .rebuildable, explanation: "Puppeteer browsers"),
        .init(relativePath: ".cache/puppeteer", risk: .rebuildable, explanation: "Puppeteer browsers"),
        .init(relativePath: "Library/Caches/CocoaPods", risk: .rebuildable, explanation: "CocoaPods download cache"),
        .init(relativePath: ".cocoapods/repos", risk: .rebuildable, explanation: "CocoaPods specs cache"),
        .init(relativePath: "Library/Caches/org.swift.swiftpm", risk: .rebuildable, explanation: "Swift Package Manager cache"),
        .init(relativePath: ".swiftpm/cache", risk: .rebuildable, explanation: "Swift Package Manager cache"),
        .init(relativePath: ".cargo/registry/cache", risk: .rebuildable, explanation: "Cargo registry cache"),
        .init(relativePath: ".cargo/git/checkouts", risk: .rebuildable, explanation: "Cargo git checkout cache"),
        .init(relativePath: "Library/Caches/go-build", risk: .rebuildable, explanation: "Go build cache"),
        .init(relativePath: "go/pkg/mod/cache", risk: .rebuildable, explanation: "Go module download cache"),
        .init(relativePath: ".cache/deno", risk: .rebuildable, explanation: "Deno dependency cache"),
        .init(relativePath: ".bun/install/cache", risk: .rebuildable, explanation: "Bun package cache")
    ]
    private let directoryStats: (any DirectoryStatProviding)?

    public init(directoryStats: (any DirectoryStatProviding)? = nil) {
        self.directoryStats = directoryStats
    }

    public func scan(homeDirectory: URL) async throws -> DeveloperStorageScanResult {
        var items: [ScannedItem] = []
        for rule in rules {
            try Task.checkCancellation()
            let root = homeDirectory.appending(path: rule.relativePath, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let rootValues = try root.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey
            ])
            guard rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true else { continue }
            let sizes: (logical: Int64, allocated: Int64)
            if let cached = try await directoryStats?.cachedDirectoryStat(at: root) {
                sizes = (
                    cached.totalLogicalSize,
                    cached.totalAllocatedSize
                )
            } else {
                sizes = try directorySizes(root)
            }
            items.append(ScannedItem(
                url: root,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                category: .developer,
                risk: rule.risk,
                explanation: rule.explanation,
                cleanupPolicyScope: DeveloperStorageCleanupPolicy.approvedRelativePaths
                    .contains(rule.relativePath) ? .developerStorage : nil,
                cleanupPolicyRelativePath: DeveloperStorageCleanupPolicy.approvedRelativePaths
                    .contains(rule.relativePath) ? rule.relativePath : nil
            ))
        }
        return DeveloperStorageScanResult(items: items.sorted { $0.allocatedSize > $1.allocatedSize })
    }

    private func directorySizes(_ root: URL) throws -> (logical: Int64, allocated: Int64) {
        try Task.checkCancellation()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return (0, 0) }
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var processed = 0
        for case let url as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            logical += Int64(values.fileSize ?? 0)
            allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        try Task.checkCancellation()
        return (logical, allocated)
    }
}
