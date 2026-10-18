import Foundation

public struct ApplicationCacheScanResult: Sendable {
    public let items: [ScannedItem]
    public let coverage: ScanCoverage

    public init(items: [ScannedItem], coverage: ScanCoverage) {
        self.items = items
        self.coverage = coverage
    }
}

/// Finds cache roots owned by installed applications using exact bundle IDs.
/// Unknown folders and protected identities are never surfaced as candidates.
public struct ApplicationCacheScanner<Access: FileSystemAccess>: Sendable {
    public static var explanation: String {
        "Application cache that can be regenerated"
    }

    private let access: Access
    private let directoryStats: (any DirectoryStatProviding)?

    public init(
        access: Access,
        directoryStats: (any DirectoryStatProviding)? = nil
    ) {
        self.access = access
        self.directoryStats = directoryStats
    }

    public func scan(
        homeDirectory: URL,
        applications: [ApplicationRecord]
    ) async throws -> ApplicationCacheScanResult {
        let applicationsByBundleID = Dictionary(
            applications.compactMap { application -> (String, ApplicationRecord)? in
                guard let identifier = application.bundleIdentifier,
                      !identifier.isEmpty,
                      !ApplicationCacheCleanupPolicy.isProtected(
                        bundleIdentifier: identifier
                      ) else {
                    return nil
                }
                return (identifier, application)
            },
            uniquingKeysWith: { first, _ in first }
        )
        guard !applicationsByBundleID.isEmpty else {
            return ApplicationCacheScanResult(items: [], coverage: .complete)
        }

        var items: [ScannedItem] = []
        var deniedPaths: [URL] = []
        var notes: [String] = []
        var visitedPaths: Set<String> = []

        let cacheRoot = homeDirectory.appending(
            path: "Library/Caches",
            directoryHint: .isDirectory
        )
        try await scanDirectChildren(
            of: cacheRoot,
            applicationsByBundleID: applicationsByBundleID,
            candidate: { child, _ in child },
            risk: .safe,
            items: &items,
            deniedPaths: &deniedPaths,
            notes: &notes,
            visitedPaths: &visitedPaths
        )

        try await scanApplicationSupportCaches(
            homeDirectory: homeDirectory,
            applications: Array(applicationsByBundleID.values),
            items: &items,
            deniedPaths: &deniedPaths,
            notes: &notes,
            visitedPaths: &visitedPaths
        )

        for application in applicationsByBundleID.values {
            guard let identifier = application.bundleIdentifier else { continue }
            for relativePath in ApplicationCacheCleanupPolicy
                .knownCacheRootsByBundleIdentifier[identifier, default: []] {
                try await appendCacheItem(
                    homeDirectory.appending(path: relativePath, directoryHint: .isDirectory),
                    application: application,
                    homeDirectory: homeDirectory,
                    risk: .safe,
                    items: &items,
                    deniedPaths: &deniedPaths,
                    notes: &notes,
                    visitedPaths: &visitedPaths
                )
            }
        }

        let containersRoot = homeDirectory.appending(
            path: "Library/Containers",
            directoryHint: .isDirectory
        )
        try await scanDirectChildren(
            of: containersRoot,
            applicationsByBundleID: applicationsByBundleID,
            candidate: { container, _ in
                container.appending(
                    path: "Data/Library/Caches",
                    directoryHint: .isDirectory
                )
            },
            risk: .rebuildable,
            items: &items,
            deniedPaths: &deniedPaths,
            notes: &notes,
            visitedPaths: &visitedPaths
        )

        try Task.checkCancellation()
        return ApplicationCacheScanResult(
            items: items.sorted {
                if $0.allocatedSize != $1.allocatedSize {
                    return $0.allocatedSize > $1.allocatedSize
                }
                return $0.url.path < $1.url.path
            },
            coverage: ScanCoverage(
                deniedPaths: Dictionary(
                    deniedPaths.map { ($0.standardizedFileURL.path, $0.standardizedFileURL) },
                    uniquingKeysWith: { first, _ in first }
                ).values.sorted { $0.path < $1.path },
                notes: Array(Set(notes)).sorted()
            )
        )
    }

    private func scanDirectChildren(
        of root: URL,
        applicationsByBundleID: [String: ApplicationRecord],
        candidate: (URL, ApplicationRecord) -> URL,
        risk: RiskLevel,
        items: inout [ScannedItem],
        deniedPaths: inout [URL],
        notes: inout [String],
        visitedPaths: inout Set<String>
    ) async throws {
        let children: [URL]
        do {
            let metadata = try access.metadata(at: root)
            guard metadata.isDirectory, !metadata.isSymbolicLink else { return }
            children = try access.contentsOfDirectory(at: root)
        } catch {
            if !Self.isMissing(error) {
                deniedPaths.append(root)
                notes.append("Could not read application cache root \(root.path): \(error.localizedDescription)")
            }
            return
        }

        for child in children {
            do {
                try Task.checkCancellation()
                let identifier = child.lastPathComponent
                guard let application = applicationsByBundleID[identifier] else { continue }
                let cacheURL = candidate(child, application).standardizedFileURL
                guard visitedPaths.insert(cacheURL.path).inserted else { continue }
                let metadata = try access.metadata(at: cacheURL)
                guard metadata.isDirectory, !metadata.isSymbolicLink else { continue }
                let sizes = try await directorySizes(at: cacheURL)
                guard sizes.allocated > 0 else { continue }
                items.append(ScannedItem(
                    url: cacheURL,
                    logicalSize: sizes.logical,
                    allocatedSize: sizes.allocated,
                    creationDate: metadata.creationDate,
                    modificationDate: metadata.modificationDate,
                    resourceIdentifier: metadata.resourceIdentifier,
                    category: .cache,
                    risk: risk,
                    ownerID: application.id,
                    explanation: Self.explanation,
                    cleanupPolicyScope: .applicationCache,
                    cleanupOwnerIdentifier: application.bundleIdentifier,
                    cleanupPolicyRelativePath: relativePath(
                        of: cacheURL,
                        under: root.deletingLastPathComponent().deletingLastPathComponent()
                    )
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if !Self.isMissing(error) {
                    guard let application = applicationsByBundleID[
                        child.lastPathComponent
                    ] else { continue }
                    let cacheURL = candidate(child, application)
                    deniedPaths.append(cacheURL)
                    notes.append("Could not inspect application cache \(cacheURL.path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func scanApplicationSupportCaches(
        homeDirectory: URL,
        applications: [ApplicationRecord],
        items: inout [ScannedItem],
        deniedPaths: inout [URL],
        notes: inout [String],
        visitedPaths: inout Set<String>
    ) async throws {
        let supportRoot = homeDirectory.appending(
            path: "Library/Application Support",
            directoryHint: .isDirectory
        )
        let children: [URL]
        do {
            let metadata = try access.metadata(at: supportRoot)
            guard metadata.isDirectory, !metadata.isSymbolicLink else { return }
            children = try access.contentsOfDirectory(at: supportRoot)
        } catch {
            if !Self.isMissing(error) {
                deniedPaths.append(supportRoot)
                notes.append("Could not read application support root \(supportRoot.path): \(error.localizedDescription)")
            }
            return
        }

        let applicationsBySupportName = Dictionary(
            applications.flatMap { application in
                Self.supportRootNames(for: application).map {
                    ($0.lowercased(), application)
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        for child in children {
            try Task.checkCancellation()
            guard let application = applicationsBySupportName[
                child.lastPathComponent.lowercased()
            ] else { continue }
            try await scanCacheLeaves(
                under: child,
                application: application,
                homeDirectory: homeDirectory,
                items: &items,
                deniedPaths: &deniedPaths,
                notes: &notes,
                visitedPaths: &visitedPaths
            )
        }

        // A few widely used products keep their support root one level below a
        // vendor folder or under a historical product name. These are exact
        // Bundle-ID rules, never fuzzy vendor/name matches.
        let knownRoots: [String: [String]] = [
            "com.google.Chrome": ["Google/Chrome"],
            "com.google.Chrome.canary": ["Google/Chrome Canary"],
            "com.microsoft.edgemac": ["Microsoft Edge"],
            "com.microsoft.VSCode": ["Code"],
            "com.microsoft.VSCodeInsiders": ["Code - Insiders"]
        ]
        for application in applications {
            guard let identifier = application.bundleIdentifier else { continue }
            for path in knownRoots[identifier, default: []] {
                try await scanCacheLeaves(
                    under: supportRoot.appending(path: path, directoryHint: .isDirectory),
                    application: application,
                    homeDirectory: homeDirectory,
                    items: &items,
                    deniedPaths: &deniedPaths,
                    notes: &notes,
                    visitedPaths: &visitedPaths
                )
            }
        }
    }

    private func scanCacheLeaves(
        under applicationSupportRoot: URL,
        application: ApplicationRecord,
        homeDirectory: URL,
        items: inout [ScannedItem],
        deniedPaths: inout [URL],
        notes: inout [String],
        visitedPaths: inout Set<String>
    ) async throws {
        let fixedLeaves = [
            "Cache", "Code Cache", "GPUCache", "ShaderCache",
            "DawnWebGPUCache", "CachedData", "component_crx_cache",
            "Crashpad/completed"
        ]
        for relativeLeaf in fixedLeaves {
            try await appendCacheItem(
                applicationSupportRoot.appending(path: relativeLeaf, directoryHint: .isDirectory),
                application: application,
                homeDirectory: homeDirectory,
                items: &items,
                deniedPaths: &deniedPaths,
                notes: &notes,
                visitedPaths: &visitedPaths
            )
        }

        let userData = applicationSupportRoot.appending(
            path: "User Data",
            directoryHint: .isDirectory
        )
        let profiles: [URL]
        do {
            let metadata = try access.metadata(at: userData)
            guard metadata.isDirectory, !metadata.isSymbolicLink else { return }
            profiles = try access.contentsOfDirectory(at: userData).filter {
                let name = $0.lastPathComponent
                return name == "Default" || name == "Guest Profile"
                    || name.hasPrefix("Profile ")
            }
        } catch {
            if !Self.isMissing(error) {
                deniedPaths.append(userData)
                notes.append("Could not read application profile caches \(userData.path): \(error.localizedDescription)")
            }
            return
        }
        let profileLeaves = [
            "Cache", "Code Cache", "GPUCache", "ShaderCache",
            "Service Worker/CacheStorage", "Service Worker/ScriptCache"
        ]
        for profile in profiles {
            for relativeLeaf in profileLeaves {
                try await appendCacheItem(
                    profile.appending(path: relativeLeaf, directoryHint: .isDirectory),
                    application: application,
                    homeDirectory: homeDirectory,
                    items: &items,
                    deniedPaths: &deniedPaths,
                    notes: &notes,
                    visitedPaths: &visitedPaths
                )
            }
        }
    }

    private func appendCacheItem(
        _ url: URL,
        application: ApplicationRecord,
        homeDirectory: URL,
        risk: RiskLevel = .rebuildable,
        items: inout [ScannedItem],
        deniedPaths: inout [URL],
        notes: inout [String],
        visitedPaths: inout Set<String>
    ) async throws {
        let cacheURL = url.standardizedFileURL
        guard visitedPaths.insert(cacheURL.path).inserted else { return }
        do {
            let metadata = try access.metadata(at: cacheURL)
            guard metadata.isDirectory, !metadata.isSymbolicLink else { return }
            let sizes = try await directorySizes(at: cacheURL)
            guard sizes.allocated > 0,
                  let relativePath = relativePath(of: cacheURL, under: homeDirectory),
                  ApplicationCacheCleanupPolicy.isApprovedRelativePath(relativePath)
            else { return }
            items.append(ScannedItem(
                url: cacheURL,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                creationDate: metadata.creationDate,
                modificationDate: metadata.modificationDate,
                resourceIdentifier: metadata.resourceIdentifier,
                category: .cache,
                risk: risk,
                ownerID: application.id,
                explanation: Self.explanation,
                cleanupPolicyScope: .applicationCache,
                cleanupOwnerIdentifier: application.bundleIdentifier,
                cleanupPolicyRelativePath: relativePath
            ))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if !Self.isMissing(error) {
                deniedPaths.append(cacheURL)
                notes.append("Could not inspect application cache \(cacheURL.path): \(error.localizedDescription)")
            }
        }
    }

    private static func supportRootNames(for application: ApplicationRecord) -> Set<String> {
        var names = Set([application.name, application.url.deletingPathExtension().lastPathComponent])
        if let identifier = application.bundleIdentifier,
           let suffix = identifier.split(separator: ".").last {
            names.insert(String(suffix))
        }
        return Set(names.filter { !$0.isEmpty && !$0.contains("/") })
    }

    private func relativePath(of url: URL, under homeDirectory: URL) -> String? {
        let homePath = homeDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(homePath + "/") else { return nil }
        return String(path.dropFirst(homePath.count + 1))
    }

    private func directorySizes(at root: URL) async throws -> (logical: Int64, allocated: Int64) {
        if let cached = try await directoryStats?.cachedDirectoryStat(at: root) {
            return (cached.totalLogicalSize, cached.totalAllocatedSize)
        }
        var pending = [root]
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var visited = 0
        while let directory = pending.popLast() {
            let children = try access.contentsOfDirectory(at: directory)
            for child in children {
                visited += 1
                if visited.isMultiple(of: 128) { try Task.checkCancellation() }
                let metadata = try access.metadata(at: child)
                guard !metadata.isSymbolicLink else { continue }
                if metadata.isDirectory {
                    if !metadata.isPackage { pending.append(child) }
                } else if metadata.isRegularFile {
                    logical += metadata.logicalSize
                    allocated += metadata.allocatedSize
                }
            }
        }
        return (logical, allocated)
    }

    private static func isMissing(_ error: Error) -> Bool {
        guard let cocoaError = error as? CocoaError else { return false }
        return cocoaError.code == .fileNoSuchFile
            || cocoaError.code == .fileReadNoSuchFile
    }
}
