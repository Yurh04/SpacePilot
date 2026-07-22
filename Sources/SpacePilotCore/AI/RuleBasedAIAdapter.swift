import Foundation

public struct RuleBasedAIAdapter: AIApplicationAdapting {
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
            for fileURL in fileURLs(beneath: root) {
                try Task.checkCancellation()
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                    .totalFileAllocatedSizeKey, .creationDateKey,
                    .contentModificationDateKey, .fileResourceIdentifierKey
                ]), values.isRegularFile == true, values.isSymbolicLink != true else { continue }

                let relativePath = relativePath(of: fileURL, beneath: root)
                let rule = rules.first { relativePath == $0.relativePathPrefix || relativePath.hasPrefix($0.relativePathPrefix + "/") }
                let category = rule?.category ?? .unclassified
                let risk = rule?.risk ?? .sensitive
                let explanation = rule?.explanation ?? "Unknown \(name) data; review before changing"
                items.append(ScannedItem(
                    url: fileURL.standardizedFileURL,
                    logicalSize: Int64(values.fileSize ?? 0),
                    allocatedSize: Int64(values.totalFileAllocatedSize ?? 0),
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate,
                    resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
                    category: category,
                    risk: risk,
                    ownerID: ownerID,
                    explanation: explanation
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

    private func fileURLs(beneath root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
                .totalFileAllocatedSizeKey, .creationDateKey,
                .contentModificationDateKey, .fileResourceIdentifierKey
            ],
            options: [.skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }
    }

    private func relativePath(of file: URL, beneath root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count + 1))
    }
}
