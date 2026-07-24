import Foundation

public struct RuleBasedAIAdapter: AIApplicationAdapting {
    private struct AssetAccumulator {
        var logicalSize: Int64 = 0
        var allocatedSize: Int64 = 0
        var fileCount = 0
        var creationDate: Date?
        var modificationDate: Date?

        mutating func add(
            logicalSize: Int64,
            allocatedSize: Int64,
            creationDate: Date?,
            modificationDate: Date?
        ) {
            self.logicalSize += logicalSize
            self.allocatedSize += allocatedSize
            fileCount += 1
            if let creationDate,
               self.creationDate == nil || creationDate < self.creationDate! {
                self.creationDate = creationDate
            }
            if let modificationDate,
               self.modificationDate == nil
                    || modificationDate > self.modificationDate! {
                self.modificationDate = modificationDate
            }
        }
    }

    private struct AssetAggregation {
        let rules: [AssetAccumulator]
        let unknown: AssetAccumulator
    }

    private static let resourceKeySet: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey
    ]
    private static let resourceKeys = Array(resourceKeySet)

    public let name: String
    public let bundleIdentifier: String?
    public let rootRelativePath: String
    public let rules: [AIAssetRule]

    public init(
        name: String,
        bundleIdentifier: String?,
        rootRelativePath: String,
        rules: [AIAssetRule]
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.rootRelativePath = rootRelativePath
        self.rules = rules.sorted { $0.relativePathPrefix.count > $1.relativePathPrefix.count }
    }

    public func scan(homeDirectory: URL) async throws -> AIApplicationScanResult {
        let root = homeDirectory.appending(path: rootRelativePath, directoryHint: .isDirectory)
        let ownerID = UUID()
        let fileManager = FileManager.default
        var items: [ScannedItem] = []

        if fileManager.fileExists(atPath: root.path) {
            let aggregation = try aggregateFiles(beneath: root)
            try Task.checkCancellation()

            for (rule, accumulator) in zip(rules, aggregation.rules)
                where accumulator.fileCount > 0 {
                items.append(ScannedItem(
                    url: aggregateURL(
                        beneath: root,
                        relativePath: rule.relativePathPrefix
                    ),
                    logicalSize: accumulator.logicalSize,
                    allocatedSize: accumulator.allocatedSize,
                    creationDate: accumulator.creationDate,
                    modificationDate: accumulator.modificationDate,
                    category: rule.category,
                    risk: rule.risk,
                    ownerID: ownerID,
                    explanation: rule.explanation
                        + " (\(accumulator.fileCount) files)"
                ))
            }
            if aggregation.unknown.fileCount > 0 {
                items.append(ScannedItem(
                    url: root.standardizedFileURL,
                    logicalSize: aggregation.unknown.logicalSize,
                    allocatedSize: aggregation.unknown.allocatedSize,
                    creationDate: aggregation.unknown.creationDate,
                    modificationDate: aggregation.unknown.modificationDate,
                    category: .unclassified,
                    risk: .sensitive,
                    ownerID: ownerID,
                    explanation: "Unknown \(name) data; review before changing"
                        + " (\(aggregation.unknown.fileCount) files)"
                ))
            }
        }

        let itemIDs = Set(items.map(\.id))
        let application = AIApplicationRecord(
            id: ownerID,
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: nil,
            rootURLs: fileManager.fileExists(atPath: root.path) ? [root] : [],
            itemIDs: itemIDs,
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .deep
        )
        let cleanupIDs = Set(items.filter { $0.risk == .safe }.map(\.id))
        return AIApplicationScanResult(
            application: application,
            items: items.sorted { $0.url.path < $1.url.path },
            cleanupRecommendedItemIDs: cleanupIDs
        )
    }

    private func aggregateURL(
        beneath root: URL,
        relativePath: String
    ) -> URL {
        let candidate = root.appending(path: relativePath).standardizedFileURL
        let isDirectory = (try? candidate.resourceValues(
            forKeys: [.isDirectoryKey]
        ).isDirectory) == true
        return URL(
            filePath: candidate.path,
            directoryHint: isDirectory ? .isDirectory : .notDirectory
        )
    }

    private func aggregateFiles(beneath root: URL) throws -> AssetAggregation {
        var ruleAccumulators = Array(
            repeating: AssetAccumulator(),
            count: rules.count
        )
        var unknownAccumulator = AssetAccumulator()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Self.resourceKeys,
            options: [.skipsPackageDescendants]
        ) else {
            return AssetAggregation(
                rules: ruleAccumulators,
                unknown: unknownAccumulator
            )
        }

        var processed = 0
        for case let fileURL as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            autoreleasepool {
                guard let values = try? fileURL.resourceValues(
                    forKeys: Self.resourceKeySet
                ), values.isRegularFile == true,
                   values.isSymbolicLink != true else {
                    return
                }
                let relativePath = relativePath(of: fileURL, beneath: root)
                let ruleIndex = rules.firstIndex {
                    relativePath == $0.relativePathPrefix
                        || relativePath.hasPrefix($0.relativePathPrefix + "/")
                }
                if let ruleIndex {
                    ruleAccumulators[ruleIndex].add(
                        logicalSize: Int64(values.fileSize ?? 0),
                        allocatedSize: Int64(
                            values.totalFileAllocatedSize
                                ?? values.fileSize
                                ?? 0
                        ),
                        creationDate: values.creationDate,
                        modificationDate: values.contentModificationDate
                    )
                } else {
                    unknownAccumulator.add(
                        logicalSize: Int64(values.fileSize ?? 0),
                        allocatedSize: Int64(
                            values.totalFileAllocatedSize
                                ?? values.fileSize
                                ?? 0
                        ),
                        creationDate: values.creationDate,
                        modificationDate: values.contentModificationDate
                    )
                }
            }
        }
        try Task.checkCancellation()
        return AssetAggregation(
            rules: ruleAccumulators,
            unknown: unknownAccumulator
        )
    }

    private func relativePath(of file: URL, beneath root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
