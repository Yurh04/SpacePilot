import Foundation

struct ApplicationArtifactSize: Equatable, Sendable {
    let logical: Int64
    let allocated: Int64
}

protocol ApplicationArtifactSizeResolving: Sendable {
    func sizes(of url: URL) async throws -> ApplicationArtifactSize
}

struct FileSystemApplicationArtifactSizeResolver:
    ApplicationArtifactSizeResolving
{
    func sizes(of url: URL) async throws -> ApplicationArtifactSize {
        try Task.checkCancellation()
        return try Self.calculateSizes(of: url)
    }

    private static func calculateSizes(
        of root: URL
    ) throws -> ApplicationArtifactSize {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .isRegularFileKey,
            .isSymbolicLinkKey
        ]
        let rootValues = try? root.resourceValues(forKeys: keys)
        if rootValues?.isRegularFile == true,
           rootValues?.isSymbolicLink != true {
            return ApplicationArtifactSize(
                logical: Int64(rootValues?.fileSize ?? 0),
                allocated: Int64(rootValues?.totalFileAllocatedSize ?? 0)
            )
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: []
        ) else {
            return ApplicationArtifactSize(logical: 0, allocated: 0)
        }

        var logical: Int64 = 0
        var allocated: Int64 = 0
        var processed = 0
        for case let url as URL in enumerator {
            processed += 1
            if processed.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true
            else {
                continue
            }
            logical += Int64(values.fileSize ?? 0)
            allocated += Int64(values.totalFileAllocatedSize ?? 0)
        }
        try Task.checkCancellation()
        return ApplicationArtifactSize(
            logical: logical,
            allocated: allocated
        )
    }
}
