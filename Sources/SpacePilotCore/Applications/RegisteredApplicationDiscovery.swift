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
              !isNestedInsideBundleContainer(url)
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
            // `/opt/` 与 `/cellar/` 是 Homebrew 工具链的固定布局目录。应用把
            // 整套 Homebrew 环境内嵌进自身沙箱时(如 TRAE SOLO CN 的
            // ModularData/.../tools/opt/python@3.10),其中的 .app 是 formula
            // 组件(Python、IDLE、Python Launcher 等),不是用户安装的应用。
            let excludedFragments = [
                "/deriveddata/",
                "/build/",
                "/caches/",
                "/updates/",
                "/workspacestorage/",
                "/globalstorage/redhat.java/",
                "/script editor/templates/",
                "/opt/",
                "/cellar/"
            ]
            guard !excludedFragments.contains(where: lowercasedPath.contains),
                  !containsSandboxEnvironmentComponent(url),
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

    /// macOS bundle 包装容器的扩展名。按 Apple 约定,嵌套在这些容器内部的
    /// `.app` 必然是该包的内部组件(如框架自带的解释器 stub、Helper),
    /// 而非独立安装的应用,因此不应进入已安装应用清单。
    private static let bundleContainerExtensions: Set<String> = [
        "app", "framework", "xpc", "plugin", "appex", "bundle"
    ]

    private func isNestedInsideBundleContainer(_ url: URL) -> Bool {
        url.deletingLastPathComponent().pathComponents.contains { component in
            guard let dotIndex = component.lastIndex(of: ".") else {
                return false
            }
            let ext = component[component.index(after: dotIndex)...].lowercased()
            return Self.bundleContainerExtensions.contains(ext)
        }
    }

    /// 判断祖先路径中是否存在 UUID 形态的目录组件。应用为每个隔离运行环境
    /// 生成 UUID 命名的目录(如 DoubaoWork 的
    /// `sandbox_envs_dir/envs/<uuid>/`),其中的 `.app` 是临时沙箱环境内的
    /// 组件,而非用户安装的应用。稳定安装布局使用语义化版本号
    /// (如 `2.1.260`、`current`),不会命中此规则。
    private func containsSandboxEnvironmentComponent(_ url: URL) -> Bool {
        url.deletingLastPathComponent().pathComponents.contains {
            Self.isUUIDComponent($0)
        }
    }

    /// 校验字符串是否为标准 UUID 形态(8-4-4-4-12 十六进制,连字符分隔)。
    private static func isUUIDComponent(_ component: String) -> Bool {
        let groupLengths = [8, 4, 4, 4, 12]
        let groups = component.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        guard groups.count == groupLengths.count else { return false }
        for (group, expectedLength) in zip(groups, groupLengths) {
            guard group.count == expectedLength,
                  group.allSatisfy(\.isHexDigit)
            else {
                return false
            }
        }
        return true
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
