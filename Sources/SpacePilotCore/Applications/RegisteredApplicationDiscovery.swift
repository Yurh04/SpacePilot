import CoreServices
import Foundation

struct RegisteredApplicationDiscovery: Sendable {
    private let homeDirectory: URL
    private let query: @Sendable () -> [URL]

    init(homeDirectory: URL) {
        self.init(
            homeDirectory: homeDirectory,
            query: Self.spotlightApplicationURLs
        )
    }

    init(
        homeDirectory: URL,
        query: @escaping @Sendable () -> [URL]
    ) {
        self.homeDirectory = homeDirectory.standardizedFileURL
        self.query = query
    }

    func applicationURLs() -> [URL] {
        query()
            .map { $0.standardizedFileURL }
            .filter(isEligibleApplicationURL)
            .uniquedByCanonicalPath()
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isEligibleApplicationURL(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "app",
              !isNestedInsideApplicationBundle(url)
        else { return false }

        let path = url.path
        let homePath = homeDirectory.path
        if path.hasPrefix("/Applications/")
            || path.hasPrefix(homePath + "/Applications/") {
            return true
        }

        if path.hasPrefix(homePath + "/Library/Application Support/")
            || path.hasPrefix("/Library/Application Support/") {
            let lowercasedPath = path.lowercased()
            let excludedFragments = [
                "/deriveddata/",
                "/build/",
                "/caches/",
                "/updates/",
                "/workspacestorage/",
                "/globalstorage/redhat.java/",
                "/script editor/templates/"
            ]
            guard !excludedFragments.contains(where: lowercasedPath.contains),
                  url.deletingPathExtension().lastPathComponent
                    .localizedCaseInsensitiveCompare("Uninstall") != .orderedSame
            else { return false }
            return true
        }

        let relativeComponents = url.pathComponents.dropFirst(
            homeDirectory.pathComponents.count
        )
        guard relativeComponents.count == 2,
              let toolchainRoot = relativeComponents.first?.lowercased()
        else { return false }
        return toolchainRoot.contains("anaconda")
            || toolchainRoot.contains("miniconda")
            || toolchainRoot.contains("mambaforge")
    }

    private func isNestedInsideApplicationBundle(_ url: URL) -> Bool {
        url.deletingLastPathComponent().pathComponents.contains {
            $0.lowercased().hasSuffix(".app")
        }
    }

    private static func spotlightApplicationURLs() -> [URL] {
        guard let query = MDQueryCreate(
            kCFAllocatorDefault,
            "kMDItemContentType == 'com.apple.application-bundle'" as CFString,
            nil,
            nil
        ), MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue))
        else { return [] }

        return (0..<MDQueryGetResultCount(query)).compactMap { index in
            let item = unsafeBitCast(
                MDQueryGetResultAtIndex(query, index),
                to: MDItem.self
            )
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String
            else { return nil }
            return URL(fileURLWithPath: path)
        }
    }
}

private extension Array where Element == URL {
    func uniquedByCanonicalPath() -> [URL] {
        var seen = Set<String>()
        return filter {
            seen.insert($0.resolvingSymlinksInPath().path).inserted
        }
    }
}
