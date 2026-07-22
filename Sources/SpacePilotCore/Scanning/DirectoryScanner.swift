import Foundation

public struct DirectoryScanOptions: Sendable {
    public let category: ItemCategory
    public let risk: RiskLevel
    public let skipPackages: Bool
    public let includeHiddenFiles: Bool

    public init(
        category: ItemCategory,
        risk: RiskLevel,
        skipPackages: Bool = true,
        includeHiddenFiles: Bool = true
    ) {
        self.category = category
        self.risk = risk
        self.skipPackages = skipPackages
        self.includeHiddenFiles = includeHiddenFiles
    }
}

public struct DirectoryScanResult: Sendable {
    public let root: URL
    public let items: [ScannedItem]
    public let coverage: ScanCoverage

    public init(root: URL, items: [ScannedItem], coverage: ScanCoverage) {
        self.root = root
        self.items = items
        self.coverage = coverage
    }
}

public struct DirectoryScanner<Access: FileSystemAccess>: Sendable {
    private let access: Access

    public init(access: Access) {
        self.access = access
    }

    public func scan(root: URL, options: DirectoryScanOptions) async throws -> DirectoryScanResult {
        var pending = [root.standardizedFileURL]
        var items: [ScannedItem] = []
        var deniedPaths: [URL] = []
        var notes: [String] = []
        var processed = 0

        while let current = pending.popLast() {
            processed += 1
            if processed.isMultiple(of: 128) {
                try Task.checkCancellation()
            }

            let children: [URL]
            do {
                children = try access.contentsOfDirectory(at: current)
            } catch {
                deniedPaths.append(current)
                notes.append("Could not read \(current.path): \(error.localizedDescription)")
                continue
            }

            for child in children {
                if !options.includeHiddenFiles, child.lastPathComponent.hasPrefix(".") {
                    continue
                }
                do {
                    let metadata = try access.metadata(at: child)
                    if metadata.isSymbolicLink { continue }
                    if metadata.isDirectory {
                        if !(options.skipPackages && metadata.isPackage) {
                            pending.append(child)
                        }
                    } else if metadata.isRegularFile {
                        items.append(ScannedItem(
                            url: child.standardizedFileURL,
                            logicalSize: metadata.logicalSize,
                            allocatedSize: metadata.allocatedSize,
                            creationDate: metadata.creationDate,
                            modificationDate: metadata.modificationDate,
                            resourceIdentifier: metadata.resourceIdentifier,
                            category: options.category,
                            risk: options.risk,
                            explanation: "Found under \(root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent)"
                        ))
                    }
                } catch {
                    deniedPaths.append(child)
                    notes.append("Could not inspect \(child.path): \(error.localizedDescription)")
                }
            }
        }

        try Task.checkCancellation()
        return DirectoryScanResult(
            root: root,
            items: items,
            coverage: ScanCoverage(
                deniedPaths: deniedPaths.sorted { $0.path < $1.path },
                notes: notes
            )
        )
    }
}
