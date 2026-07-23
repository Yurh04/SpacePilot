import Foundation

public struct CleanupCandidateRefresher: Sendable {
    public init() {}

    public func refresh(item: ScannedItem, policy: PathSafetyPolicy) throws -> CleanupCandidate {
        try Task.checkCancellation()
        let url = try policy.validate(item.url)
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ])
        let kind: CleanupItemKind
        let size: Int64
        if values.isDirectory == true {
            kind = .directory
            size = try recursiveAllocatedSize(of: url)
        } else if values.isRegularFile == true {
            kind = .regularFile
            size = Int64(values.totalFileAllocatedSize ?? 0)
        } else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard let resourceIdentifier = values.fileResourceIdentifier else {
            throw CocoaError(.fileReadUnknown)
        }
        return CleanupCandidate(
            itemID: item.id,
            url: url,
            allocatedSize: size,
            risk: item.risk,
            itemKind: kind,
            expectedResourceIdentifier: String(describing: resourceIdentifier),
            expectedModificationDate: values.contentModificationDate,
            explanation: item.explanation
        )
    }

    private func recursiveAllocatedSize(of root: URL) throws -> Int64 {
        try Task.checkCancellation()
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey],
            options: [.skipsPackageDescendants]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
