import Foundation

public enum PluginDiscoveryDiagnostic: String, Codable, Hashable, Sendable {
    case cacheInaccessible = "Plugin cache could not be accessed"
    case sourceInaccessible = "A Plugin source could not be accessed"
    case pluginDirectoryInaccessible = "A Plugin directory could not be accessed"
    case installationInaccessible = "A Plugin installation could not be accessed"

    public var message: String { rawValue }
}

public struct PluginRootDiscoveryResult: Sendable {
    public let roots: [URL]
    public let diagnostics: [PluginDiscoveryDiagnostic]

    public init(roots: [URL], diagnostics: [PluginDiscoveryDiagnostic]) {
        self.roots = roots
        self.diagnostics = diagnostics
    }
}

public struct PluginRootDiscovery<Access: FileSystemAccess>: Sendable {
    private let access: Access

    public init(access: Access) {
        self.access = access
    }

    public func discover(homeDirectory: URL) -> PluginRootDiscoveryResult {
        let cache = homeDirectory.appending(path: ".codex/plugins/cache", directoryHint: .isDirectory)
        do {
            guard try access.metadata(at: cache).isDirectory else {
                return result(roots: [], diagnostics: [.cacheInaccessible])
            }
        } catch where isFileNotFound(error) {
            return result(roots: [], diagnostics: [])
        } catch {
            return result(roots: [], diagnostics: [.cacheInaccessible])
        }

        let sources: [URL]
        do {
            sources = try access.contentsOfDirectory(at: cache)
        } catch {
            return result(roots: [], diagnostics: [.cacheInaccessible])
        }

        var roots = Set<URL>()
        var diagnostics = Set<PluginDiscoveryDiagnostic>()
        for source in sources.sorted(by: pathOrder) {
            guard isDirectory(source, failure: .sourceInaccessible, diagnostics: &diagnostics) else {
                continue
            }
            let pluginDirectories: [URL]
            do {
                pluginDirectories = try access.contentsOfDirectory(at: source)
            } catch {
                diagnostics.insert(.sourceInaccessible)
                continue
            }

            for pluginDirectory in pluginDirectories.sorted(by: pathOrder) {
                guard isDirectory(
                    pluginDirectory,
                    failure: .pluginDirectoryInaccessible,
                    diagnostics: &diagnostics
                ) else { continue }
                let installations: [URL]
                do {
                    installations = try access.contentsOfDirectory(at: pluginDirectory)
                } catch {
                    diagnostics.insert(.pluginDirectoryInaccessible)
                    continue
                }

                for installation in installations.sorted(by: pathOrder) {
                    guard isDirectory(
                        installation,
                        failure: .installationInaccessible,
                        diagnostics: &diagnostics
                    ) else { continue }
                    roots.insert(installation.standardizedFileURL)
                }
            }
        }
        return result(roots: Array(roots), diagnostics: Array(diagnostics))
    }

    private func isDirectory(
        _ url: URL,
        failure: PluginDiscoveryDiagnostic,
        diagnostics: inout Set<PluginDiscoveryDiagnostic>
    ) -> Bool {
        do {
            return try access.metadata(at: url).isDirectory
        } catch {
            diagnostics.insert(failure)
            return false
        }
    }

    private func result(
        roots: [URL],
        diagnostics: [PluginDiscoveryDiagnostic]
    ) -> PluginRootDiscoveryResult {
        PluginRootDiscoveryResult(
            roots: roots.sorted(by: pathOrder),
            diagnostics: diagnostics.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private func pathOrder(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.path < rhs.path
    }

    private func isFileNotFound(_ error: Error) -> Bool {
        (error as? CocoaError)?.code == .fileNoSuchFile
    }
}
