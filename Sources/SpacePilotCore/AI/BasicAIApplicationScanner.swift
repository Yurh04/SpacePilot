import Foundation

public struct BasicAIApplicationScanner: Sendable {
    public init() {}

    public func scan(
        name: String,
        bundleIdentifier: String?,
        homeDirectory: URL,
        relativeRoots: [String]
    ) async throws -> AIApplicationScanResult {
        let ownerID = UUID()
        let roots = relativeRoots
            .map { homeDirectory.appending(path: $0, directoryHint: .isDirectory) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        var items: [ScannedItem] = []

        for root in roots {
            try Task.checkCancellation()
            let sizes = directorySizes(root)
            items.append(ScannedItem(
                url: root,
                logicalSize: sizes.logical,
                allocatedSize: sizes.allocated,
                category: .aiData,
                risk: .sensitive,
                ownerID: ownerID,
                explanation: "Recognized \(name) data root; contents were not indexed"
            ))
        }

        let application = AIApplicationRecord(
            id: ownerID,
            name: name,
            bundleIdentifier: bundleIdentifier,
            applicationURL: nil,
            rootURLs: roots,
            itemIDs: Set(items.map(\.id)),
            pluginIDs: [],
            skillIDs: [],
            applicationAllocatedSize: 0,
            supportLevel: .basic
        )
        return AIApplicationScanResult(application: application, items: items)
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
