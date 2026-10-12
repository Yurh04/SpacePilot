import Foundation

/// Result of scanning well-known download locations for application installer
/// files that are safe to remove once the application is installed.
public struct InstallerPackageScanResult: Sendable {
    public let items: [ScannedItem]
    public let coverage: ScanCoverage
    /// Bytes contained inside `.pkg`/`.mpkg` package directories. A whole-home
    /// traversal skips package descendants, so these bytes are not part of the
    /// personal-files total and must not be subtracted again during aggregation.
    public let packageContainedLogicalSize: Int64
    public let packageContainedAllocatedSize: Int64
    /// Number of regular files nested inside installer package directories.
    public let packageContainedFileCount: Int

    public init(
        items: [ScannedItem],
        coverage: ScanCoverage,
        packageContainedLogicalSize: Int64,
        packageContainedAllocatedSize: Int64,
        packageContainedFileCount: Int
    ) {
        self.items = items
        self.coverage = coverage
        self.packageContainedLogicalSize = max(0, packageContainedLogicalSize)
        self.packageContainedAllocatedSize = max(0, packageContainedAllocatedSize)
        self.packageContainedFileCount = max(0, packageContainedFileCount)
    }

    static let empty = InstallerPackageScanResult(
        items: [],
        coverage: .complete,
        packageContainedLogicalSize: 0,
        packageContainedAllocatedSize: 0,
        packageContainedFileCount: 0
    )
}

/// Discovers downloaded application installers (`.dmg` disk images and
/// `.pkg`/`.mpkg` installer packages) in bounded, well-known locations such as
/// the user's Downloads and Desktop folders.
///
/// The scan is intentionally shallow: only a few directory levels below the
/// provided roots are inspected, package and bundle descendants are not
/// traversed, and every match is classified as `ItemCategory.installer` with
/// `RiskLevel.safe` because installers can be downloaded again after the
/// application has been installed.
public struct InstallerPackageScanner<Access: FileSystemAccess>: Sendable {
    /// Extensions treated as installers when found as regular files.
    public static var diskImagePathExtension: String { "dmg" }
    public static var packagePathExtensions: Set<String> { ["pkg", "mpkg"] }
    public static var supportedPathExtensions: Set<String> {
        packagePathExtensions.union([diskImagePathExtension])
    }

    /// How many regular directory levels are inspected below each root.
    public static var defaultMaximumDirectoryDepth: Int { 3 }
    /// Upper bound on retained installer items; the largest items win.
    public static var defaultRetainedItemLimit: Int { 1_000 }

    private let access: Access
    private let maximumDirectoryDepth: Int
    private let retainedItemLimit: Int

    public init(
        access: Access,
        maximumDirectoryDepth: Int = InstallerPackageScanner.defaultMaximumDirectoryDepth,
        retainedItemLimit: Int = InstallerPackageScanner.defaultRetainedItemLimit
    ) {
        self.access = access
        self.maximumDirectoryDepth = max(0, maximumDirectoryDepth)
        self.retainedItemLimit = max(0, retainedItemLimit)
    }

    public func scan(roots: [URL]) async throws -> InstallerPackageScanResult {
        var discovered: [ScannedItem] = []
        var deniedPaths: [URL] = []
        var notes: [String] = []
        var packageLogicalSize: Int64 = 0
        var packageAllocatedSize: Int64 = 0
        var packageFileCount = 0
        var inspectedEntries = 0

        for root in roots {
            try Task.checkCancellation()
            let root = root.standardizedFileURL
            let metadata: FileMetadata
            do {
                metadata = try access.metadata(at: root)
            } catch {
                // A missing Downloads/Desktop folder is normal; only readable
                // roots participate in the scan.
                continue
            }
            guard metadata.isDirectory, !metadata.isSymbolicLink else { continue }

            var pending: [(url: URL, depth: Int)] = [(root, 0)]
            while let (current, depth) = pending.popLast() {
                let children: [URL]
                do {
                    children = try access.contentsOfDirectory(at: current)
                } catch {
                    deniedPaths.append(current)
                    notes.append("Could not read \(current.path): \(error.localizedDescription)")
                    continue
                }
                for child in children {
                    inspectedEntries += 1
                    if inspectedEntries.isMultiple(of: 512) {
                        try Task.checkCancellation()
                    }
                    if child.lastPathComponent.hasPrefix(".") {
                        continue
                    }
                    let childMetadata: FileMetadata
                    do {
                        childMetadata = try access.metadata(at: child)
                    } catch {
                        deniedPaths.append(child)
                        notes.append("Could not inspect \(child.path): \(error.localizedDescription)")
                        continue
                    }
                    if childMetadata.isSymbolicLink {
                        continue
                    }
                    let `extension` = child.pathExtension.lowercased()
                    if childMetadata.isDirectory {
                        if Self.packagePathExtensions.contains(`extension`) {
                            let contained = try packageContents(of: child)
                            packageLogicalSize += contained.logicalSize
                            packageAllocatedSize += contained.allocatedSize
                            packageFileCount += contained.fileCount
                            discovered.append(ScannedItem(
                                url: child.standardizedFileURL,
                                logicalSize: contained.logicalSize,
                                allocatedSize: contained.allocatedSize,
                                creationDate: childMetadata.creationDate,
                                modificationDate: childMetadata.modificationDate,
                                resourceIdentifier: childMetadata.resourceIdentifier,
                                category: .installer,
                                risk: .safe,
                                explanation: Self.explanation
                            ))
                        } else if !childMetadata.isPackage,
                                  depth < maximumDirectoryDepth {
                            pending.append((child.standardizedFileURL, depth + 1))
                        }
                    } else if childMetadata.isRegularFile,
                              Self.supportedPathExtensions.contains(`extension`) {
                        discovered.append(ScannedItem(
                            url: child.standardizedFileURL,
                            logicalSize: childMetadata.logicalSize,
                            allocatedSize: childMetadata.allocatedSize,
                            creationDate: childMetadata.creationDate,
                            modificationDate: childMetadata.modificationDate,
                            resourceIdentifier: childMetadata.resourceIdentifier,
                            category: .installer,
                            risk: .safe,
                            explanation: Self.explanation
                        ))
                    }
                }
            }
        }

        let items = Array(discovered.sorted {
            if $0.allocatedSize != $1.allocatedSize {
                return $0.allocatedSize > $1.allocatedSize
            }
            if $0.logicalSize != $1.logicalSize {
                return $0.logicalSize > $1.logicalSize
            }
            return $0.url.path < $1.url.path
        }.prefix(max(0, retainedItemLimit)))

        return InstallerPackageScanResult(
            items: items,
            coverage: ScanCoverage(
                deniedPaths: deniedPaths.sorted { $0.path < $1.path },
                notes: notes
            ),
            packageContainedLogicalSize: packageLogicalSize,
            packageContainedAllocatedSize: packageAllocatedSize,
            packageContainedFileCount: packageFileCount
        )
    }

    static var explanation: String {
        "Application installer; safe to remove after the app is installed"
    }

    private func packageContents(of packageURL: URL) throws -> (
        logicalSize: Int64, allocatedSize: Int64, fileCount: Int
    ) {
        var pending = [packageURL]
        var logicalSize: Int64 = 0
        var allocatedSize: Int64 = 0
        var fileCount = 0
        var inspected = 0
        while let current = pending.popLast() {
            inspected += 1
            if inspected.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let children: [URL]
            do {
                children = try access.contentsOfDirectory(at: current)
            } catch {
                continue
            }
            for child in children {
                let metadata: FileMetadata
                do {
                    metadata = try access.metadata(at: child)
                } catch {
                    continue
                }
                if metadata.isSymbolicLink {
                    continue
                }
                if metadata.isDirectory {
                    pending.append(child)
                } else if metadata.isRegularFile {
                    logicalSize += metadata.logicalSize
                    allocatedSize += metadata.allocatedSize
                    fileCount += 1
                }
            }
        }
        return (logicalSize, allocatedSize, fileCount)
    }
}
