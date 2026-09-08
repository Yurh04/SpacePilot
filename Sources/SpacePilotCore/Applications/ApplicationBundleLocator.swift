import Foundation

enum ApplicationBundleLocator {
    static let maximumContainerDepth = 4

    static func applicationURLs(
        in location: URL,
        maximumDepth: Int = maximumContainerDepth
    ) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: location,
            includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var applications: [URL] = []
        for case let candidate as URL in enumerator {
            try Task.checkCancellation()
            if enumerator.level > maximumDepth {
                enumerator.skipDescendants()
                continue
            }
            guard candidate.pathExtension.lowercased() == "app" else { continue }
            let values = try? candidate.resourceValues(forKeys: [
                .isDirectoryKey,
                .isPackageKey
            ])
            guard values?.isDirectory == true else { continue }
            applications.append(candidate)
            enumerator.skipDescendants()
        }
        return applications
    }
}
