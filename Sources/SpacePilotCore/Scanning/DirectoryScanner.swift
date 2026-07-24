import Foundation

public struct DirectoryScanOptions: Sendable {
    public let category: ItemCategory
    public let risk: RiskLevel
    public let skipPackages: Bool
    public let includeHiddenFiles: Bool
    public let retainedItemLimit: Int?

    public init(
        category: ItemCategory,
        risk: RiskLevel,
        skipPackages: Bool = true,
        includeHiddenFiles: Bool = true,
        retainedItemLimit: Int? = nil
    ) {
        self.category = category
        self.risk = risk
        self.skipPackages = skipPackages
        self.includeHiddenFiles = includeHiddenFiles
        self.retainedItemLimit = retainedItemLimit.map { max(0, $0) }
    }
}

public struct DirectoryScanResult: Sendable {
    public let root: URL
    public let items: [ScannedItem]
    public let coverage: ScanCoverage
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let fileCount: Int

    public init(
        root: URL,
        items: [ScannedItem],
        coverage: ScanCoverage,
        totalLogicalSize: Int64? = nil,
        totalAllocatedSize: Int64? = nil,
        fileCount: Int? = nil
    ) {
        self.root = root
        self.items = items
        self.coverage = coverage
        self.totalLogicalSize = totalLogicalSize
            ?? items.reduce(Int64(0)) { $0 + $1.logicalSize }
        self.totalAllocatedSize = totalAllocatedSize
            ?? items.reduce(Int64(0)) { $0 + $1.allocatedSize }
        self.fileCount = fileCount ?? items.count
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
        var retainedItems = LargestItemSelection(
            limit: options.retainedItemLimit ?? .max
        )
        var deniedPaths: [URL] = []
        var notes: [String] = []
        var processed = 0
        var totalLogicalSize: Int64 = 0
        var totalAllocatedSize: Int64 = 0
        var fileCount = 0

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
                        totalLogicalSize += metadata.logicalSize
                        totalAllocatedSize += metadata.allocatedSize
                        fileCount += 1
                        let item = ScannedItem(
                            url: child.standardizedFileURL,
                            logicalSize: metadata.logicalSize,
                            allocatedSize: metadata.allocatedSize,
                            creationDate: metadata.creationDate,
                            modificationDate: metadata.modificationDate,
                            resourceIdentifier: metadata.resourceIdentifier,
                            category: options.category,
                            risk: options.risk,
                            explanation: "Found under \(root.lastPathComponent.isEmpty ? root.path : root.lastPathComponent)"
                        )
                        if options.retainedItemLimit == nil {
                            items.append(item)
                        } else {
                            retainedItems.insert(item)
                        }
                    }
                } catch {
                    deniedPaths.append(child)
                    notes.append("Could not inspect \(child.path): \(error.localizedDescription)")
                }
            }
        }

        try Task.checkCancellation()
        if options.retainedItemLimit != nil {
            items = retainedItems.sortedItems
        }
        return DirectoryScanResult(
            root: root,
            items: items,
            coverage: ScanCoverage(
                deniedPaths: deniedPaths.sorted { $0.path < $1.path },
                notes: notes
            ),
            totalLogicalSize: totalLogicalSize,
            totalAllocatedSize: totalAllocatedSize,
            fileCount: fileCount
        )
    }
}

private struct LargestItemSelection {
    let limit: Int
    private var heap: [ScannedItem] = []

    init(limit: Int) {
        self.limit = limit
    }

    var sortedItems: [ScannedItem] {
        heap.sorted {
            if $0.allocatedSize != $1.allocatedSize {
                return $0.allocatedSize > $1.allocatedSize
            }
            if $0.logicalSize != $1.logicalSize {
                return $0.logicalSize > $1.logicalSize
            }
            return $0.url.path < $1.url.path
        }
    }

    mutating func insert(_ item: ScannedItem) {
        guard limit > 0 else { return }
        if heap.count < limit {
            heap.append(item)
            siftUp(from: heap.count - 1)
        } else if isPreferred(item, to: heap[0]) {
            heap[0] = item
            siftDown(from: 0)
        }
    }

    private func isPreferred(_ lhs: ScannedItem, to rhs: ScannedItem) -> Bool {
        if lhs.allocatedSize != rhs.allocatedSize {
            return lhs.allocatedSize > rhs.allocatedSize
        }
        if lhs.logicalSize != rhs.logicalSize {
            return lhs.logicalSize > rhs.logicalSize
        }
        return lhs.url.path < rhs.url.path
    }

    private func isWorse(_ lhs: ScannedItem, than rhs: ScannedItem) -> Bool {
        isPreferred(rhs, to: lhs)
    }

    private mutating func siftUp(from startIndex: Int) {
        var child = startIndex
        while child > 0 {
            let parent = (child - 1) / 2
            guard isWorse(heap[child], than: heap[parent]) else { return }
            heap.swapAt(child, parent)
            child = parent
        }
    }

    private mutating func siftDown(from startIndex: Int) {
        var parent = startIndex
        while true {
            let left = parent * 2 + 1
            guard left < heap.count else { return }
            let right = left + 1
            var worseChild = left
            if right < heap.count, isWorse(heap[right], than: heap[left]) {
                worseChild = right
            }
            guard isWorse(heap[worseChild], than: heap[parent]) else { return }
            heap.swapAt(parent, worseChild)
            parent = worseChild
        }
    }
}
