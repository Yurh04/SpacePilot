import Foundation

struct ManagedAssetDirectoryMetadata {
    let allocatedSize: Int64
    let relativeFileNames: [String]

    static func scan(root: URL) -> Self {
        let resourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else { return Self(allocatedSize: 0, relativeFileNames: []) }

        let rootPath = root.standardizedFileURL.path
        let descendantPrefix = rootPath == "/" ? "/" : rootPath + "/"
        var allocatedSize: Int64 = 0
        var relativeFileNames: [String] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: resourceKeys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            let filePath = url.standardizedFileURL.path
            guard filePath.hasPrefix(descendantPrefix) else { continue }
            allocatedSize += Int64(values.totalFileAllocatedSize ?? 0)
            relativeFileNames.append(String(filePath.dropFirst(descendantPrefix.count)))
        }
        return Self(allocatedSize: allocatedSize, relativeFileNames: relativeFileNames)
    }
}
