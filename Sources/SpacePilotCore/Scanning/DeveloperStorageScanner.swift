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

    private struct SimctlDeviceList: Decodable {
        let devices: [String: [SimctlDevice]]
    }

    private struct SimctlDevice: Decodable {
        let name: String
        let udid: String
        let state: String?
        let isAvailable: Bool?
        let lastBootedAt: String?
    }

    private struct SimctlRuntime: Decodable {
        let build: String?
        let identifier: String
        let lastUsedAt: String?
        let mountPath: String?
        let runtimeBundlePath: String?
        let runtimeIdentifier: String?
        let sizeBytes: Int64?
        let state: String?
        let version: String?
    }

    private struct DeviceInventory: Sendable {
        let name: String
        let udid: String
        let runtimeIdentifier: String
        let state: String?
        let isAvailable: Bool?
        let lastBootedAt: Date?
    }

    private static let rules: [Rule] = [
        .init(relativePath: "Library/Developer/Xcode/DerivedData", risk: .rebuildable, explanation: "Xcode build products and indexes"),
        .init(relativePath: "Library/Developer/Xcode/Archives", risk: .sensitive, explanation: "Xcode release archives"),
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
    private let processRunner: any CLIProcessRunning

    public init(
        directoryStats: (any DirectoryStatProviding)? = nil,
        processRunner: any CLIProcessRunning = DefaultCLIProcessRunner()
    ) {
        self.directoryStats = directoryStats
        self.processRunner = processRunner
    }

    public func scan(homeDirectory: URL) async throws -> DeveloperStorageScanResult {
        var items = try await scanKnownToolRoots(homeDirectory: homeDirectory)
        items.append(contentsOf: try await scanSimulators(homeDirectory: homeDirectory))
        return DeveloperStorageScanResult(items: items.sorted {
            if $0.allocatedSize != $1.allocatedSize {
                return $0.allocatedSize > $1.allocatedSize
            }
            return $0.url.path < $1.url.path
        })
    }

    public static func owns(_ item: ScannedItem, homeDirectory: URL) -> Bool {
        if item.developerStorageMetadata != nil { return true }
        if item.cleanupPolicyScope == .developerStorage { return true }
        let home = homeDirectory.standardizedFileURL.path
        let path = item.url.standardizedFileURL.path
        let coreSimulator = homeDirectory.appending(
            path: "Library/Developer/CoreSimulator",
            directoryHint: .isDirectory
        ).standardizedFileURL.path
        if path == coreSimulator { return true }
        return Self.rules.contains {
            path == homeDirectory.appending(
                path: $0.relativePath,
                directoryHint: .isDirectory
            ).standardizedFileURL.path
        } && path.hasPrefix(home + "/")
    }

    private func scanKnownToolRoots(homeDirectory: URL) async throws -> [ScannedItem] {
        var items: [ScannedItem] = []
        for rule in Self.rules {
            try Task.checkCancellation()
            let root = homeDirectory.appending(path: rule.relativePath, directoryHint: .isDirectory)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let rootValues = try root.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey
            ])
            guard rootValues.isDirectory == true,
                  rootValues.isSymbolicLink != true else { continue }
            let sizes = try await sizes(for: root)
            let approved = DeveloperStorageCleanupPolicy.approvedRelativePaths
                .contains(rule.relativePath)
            items.append(ScannedItem(
                url: root,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                category: .developer,
                risk: rule.risk,
                explanation: rule.explanation,
                cleanupPolicyScope: approved ? .developerStorage : nil,
                cleanupPolicyRelativePath: approved ? rule.relativePath : nil,
                developerStorageMetadata: DeveloperStorageMetadata(
                    kind: .toolCache,
                    name: rule.explanation
                )
            ))
        }
        return items
    }

    private func scanSimulators(homeDirectory: URL) async throws -> [ScannedItem] {
        let devicesRoot = homeDirectory.appending(
            path: "Library/Developer/CoreSimulator/Devices",
            directoryHint: .isDirectory
        )
        let isCurrentUserHome = homeDirectory.standardizedFileURL
            == FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        guard isCurrentUserHome
                || FileManager.default.fileExists(atPath: devicesRoot.path) else {
            return []
        }
        async let deviceData = simctl(
            arguments: ["simctl", "list", "devices", "-j"],
            homeDirectory: homeDirectory
        )
        async let runtimeData = simctl(
            arguments: ["simctl", "runtime", "list", "-j"],
            homeDirectory: homeDirectory
        )
        let (deviceOutput, runtimeOutput) = await (deviceData, runtimeData)
        let devices = decodeDevices(deviceOutput)
        let runtimes = decodeRuntimes(runtimeOutput)
        let runtimeByIdentifier = Dictionary(
            runtimes.compactMap { runtime -> (String, SimctlRuntime)? in
                guard let identifier = runtime.runtimeIdentifier else { return nil }
                return (identifier, runtime)
            },
            uniquingKeysWith: { first, _ in first }
        )
        let deviceInventory = devices.isEmpty
            ? fallbackDevices(homeDirectory: homeDirectory)
            : devices

        var items = try await simulatorDeviceItems(
            devices: deviceInventory,
            runtimes: runtimeByIdentifier,
            homeDirectory: homeDirectory
        )
        items.append(contentsOf: simulatorRuntimeItems(
            runtimes: runtimes,
            devices: deviceInventory
        ))
        return items
    }

    private func simulatorDeviceItems(
        devices: [DeviceInventory],
        runtimes: [String: SimctlRuntime],
        homeDirectory: URL
    ) async throws -> [ScannedItem] {
        let devicesRoot = homeDirectory.appending(
            path: "Library/Developer/CoreSimulator/Devices",
            directoryHint: .isDirectory
        ).standardizedFileURL
        var result: [ScannedItem] = []
        for device in devices {
            try Task.checkCancellation()
            guard UUID(uuidString: device.udid) != nil else { continue }
            let root = devicesRoot.appending(path: device.udid, directoryHint: .isDirectory)
                .standardizedFileURL
            guard root.deletingLastPathComponent().path == devicesRoot.path,
                  FileManager.default.fileExists(atPath: root.path),
                  (try? root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                    .map({ $0.isDirectory == true && $0.isSymbolicLink != true }) == true else {
                continue
            }
            let sizes = try await sizes(for: root)
            let runtime = runtimes[device.runtimeIdentifier]
            result.append(ScannedItem(
                url: root,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                category: .developer,
                risk: .sensitive,
                explanation: "Simulator device",
                developerStorageMetadata: DeveloperStorageMetadata(
                    kind: .simulatorDevice,
                    name: device.name,
                    runtimeIdentifier: device.runtimeIdentifier,
                    runtimeVersion: runtime?.version ?? Self.runtimeVersion(from: device.runtimeIdentifier),
                    buildVersion: runtime?.build,
                    state: device.state,
                    lastUsedDate: device.lastBootedAt,
                    isAvailable: device.isAvailable,
                    isInUse: device.state?.localizedCaseInsensitiveCompare("Booted") == .orderedSame
                )
            ))
        }
        return result
    }

    private func simulatorRuntimeItems(
        runtimes: [SimctlRuntime],
        devices: [DeviceInventory]
    ) -> [ScannedItem] {
        let usedRuntimeIDs = Set(devices.map(\.runtimeIdentifier))
        return runtimes.compactMap { runtime in
            guard let runtimeIdentifier = runtime.runtimeIdentifier,
                  let size = runtime.sizeBytes,
                  size > 0,
                  let path = runtime.runtimeBundlePath ?? runtime.mountPath,
                  Self.isApprovedRuntimePath(path) else { return nil }
            return ScannedItem(
                url: URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL,
                logicalSize: size,
                allocatedSize: size,
                category: .developer,
                risk: .sensitive,
                explanation: "Simulator runtime",
                developerStorageMetadata: DeveloperStorageMetadata(
                    kind: .simulatorRuntime,
                    name: Self.runtimePlatformName(from: runtimeIdentifier),
                    runtimeIdentifier: runtimeIdentifier,
                    runtimeVersion: runtime.version,
                    buildVersion: runtime.build,
                    state: runtime.state,
                    lastUsedDate: Self.date(runtime.lastUsedAt),
                    isAvailable: runtime.state == nil ? nil : runtime.state == "Ready",
                    isInUse: usedRuntimeIDs.contains(runtimeIdentifier)
                )
            )
        }
    }

    private func simctl(arguments: [String], homeDirectory: URL) async -> Data? {
        do {
            let output = try await processRunner.run(
                executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: arguments,
                environment: [
                    "HOME": homeDirectory.path,
                    "LANG": "C",
                    "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"
                ],
                timeout: .seconds(8),
                maximumOutputBytes: 2 * 1_024 * 1_024
            )
            guard output.terminationStatus == 0,
                  !output.didTimeout,
                  !output.outputTruncated else { return nil }
            return output.standardOutput
        } catch {
            return nil
        }
    }

    private func decodeDevices(_ data: Data?) -> [DeviceInventory] {
        guard let data,
              let decoded = try? JSONDecoder().decode(SimctlDeviceList.self, from: data) else {
            return []
        }
        return decoded.devices.flatMap { runtimeIdentifier, devices in
            devices.map {
                DeviceInventory(
                    name: $0.name,
                    udid: $0.udid,
                    runtimeIdentifier: runtimeIdentifier,
                    state: $0.state,
                    isAvailable: $0.isAvailable,
                    lastBootedAt: Self.date($0.lastBootedAt)
                )
            }
        }
    }

    private func decodeRuntimes(_ data: Data?) -> [SimctlRuntime] {
        guard let data,
              let dictionary = try? JSONDecoder().decode([String: SimctlRuntime].self, from: data) else {
            return []
        }
        return dictionary.values.sorted {
            ($0.runtimeIdentifier ?? $0.identifier) < ($1.runtimeIdentifier ?? $1.identifier)
        }
    }

    private func fallbackDevices(homeDirectory: URL) -> [DeviceInventory] {
        let root = homeDirectory.appending(
            path: "Library/Developer/CoreSimulator/Devices",
            directoryHint: .isDirectory
        )
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return children.compactMap { child in
            guard UUID(uuidString: child.lastPathComponent) != nil,
                  let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true,
                  values.isSymbolicLink != true,
                  let data = try? Data(contentsOf: child.appending(path: "device.plist")),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any],
                  let name = plist["name"] as? String,
                  let runtime = plist["runtime"] as? String else { return nil }
            return DeviceInventory(
                name: name,
                udid: child.lastPathComponent,
                runtimeIdentifier: runtime,
                state: nil,
                isAvailable: nil,
                lastBootedAt: plist["lastBootedAt"] as? Date
            )
        }
    }

    private func sizes(for root: URL) async throws -> (logical: Int64, allocated: Int64) {
        if let cached = try await directoryStats?.cachedDirectoryStat(at: root) {
            return (cached.totalLogicalSize, cached.totalAllocatedSize)
        }
        return try directorySizes(root)
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

    private static func date(_ source: String?) -> Date? {
        guard let source else { return nil }
        return ISO8601DateFormatter().date(from: source)
    }

    private static func runtimeVersion(from identifier: String) -> String? {
        guard let marker = identifier.range(of: ".SimRuntime.") else { return nil }
        let suffix = identifier[marker.upperBound...]
        guard let separator = suffix.firstIndex(of: "-") else { return nil }
        return suffix[suffix.index(after: separator)...]
            .replacingOccurrences(of: "-", with: ".")
    }

    private static func runtimePlatformName(from identifier: String) -> String {
        guard let marker = identifier.range(of: ".SimRuntime.") else { return "Simulator" }
        return String(identifier[marker.upperBound...].split(separator: "-").first ?? "Simulator")
    }

    private static func isApprovedRuntimePath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.hasPrefix("/Library/Developer/CoreSimulator/Volumes/")
            || standardized.hasPrefix("/System/Library/AssetsV2/")
    }
}
