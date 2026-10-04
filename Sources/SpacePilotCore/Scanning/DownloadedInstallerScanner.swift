import Foundation

public enum DownloadedInstallerRefreshPlanner {
    private static let supportedExtensions: Set<String> = ["dmg", "pkg", "mpkg"]
    private static let partialExtensions: Set<String> = ["download", "part", "crdownload"]

    public static func shouldRefresh(
        for batch: FileSystemChangeBatch,
        downloadsDirectory: URL
    ) -> Bool {
        if batch.requiresFullInvalidation { return true }
        let root = downloadsDirectory.standardizedFileURL.path
        return batch.changedPaths.contains { changedPath in
            let url = changedPath.standardizedFileURL
            let path = url.path
            guard path == root || path.hasPrefix(root + "/") else { return false }
            if path == root { return true }

            let pathExtension = url.pathExtension.lowercased()
            if supportedExtensions.contains(pathExtension) { return true }
            guard partialExtensions.contains(pathExtension) else { return false }
            return supportedExtensions.contains(
                url.deletingPathExtension().pathExtension.lowercased()
            )
        }
    }
}

/// Finds installer packages that can be tied to an application already present
/// in the application inventory. The scan is deliberately shallow and the
/// matching deliberately strict so a document archive is never promoted to a
/// cleanup candidate merely because it contains an application name.
public struct DownloadedInstallerScanner<Access: FileSystemAccess>: Sendable {
    private static var supportedExtensions: Set<String> {
        ["dmg", "pkg", "mpkg"]
    }
    private static var genericBundleComponents: Set<String> {
        ["app", "application", "client", "desktop", "helper", "launcher", "mac"]
    }
    private static var permittedSuffixes: [String] {
        [
            "applesilicon", "universal2", "universal", "installer", "download",
            "aarch64", "darwin", "stable", "release", "arm64", "x8664",
            "macosx", "macos", "install", "intel", "setup", "osx", "mac"
        ].sorted { $0.count > $1.count }
    }

    private let access: Access

    public init(access: Access) {
        self.access = access
    }

    public func scan(
        downloadsDirectory: URL,
        applications: [ApplicationRecord]
    ) async throws -> DirectoryScanResult {
        let root = downloadsDirectory.standardizedFileURL
        let children: [URL]
        do {
            children = try access.contentsOfDirectory(at: root)
        } catch {
            if Self.isMissingDirectory(error) {
                return DirectoryScanResult(root: root, items: [], coverage: .complete)
            }
            return DirectoryScanResult(
                root: root,
                items: [],
                coverage: ScanCoverage(
                    deniedPaths: [root],
                    notes: ["Could not read Downloads for installer packages: \(error.localizedDescription)"]
                )
            )
        }

        let homeDirectory = root.deletingLastPathComponent()
        let installedApplications = applications.filter {
            Self.isInstalledApplication($0, homeDirectory: homeDirectory)
        }
        let aliases = Self.applicationAliases(installedApplications)
        var items: [ScannedItem] = []
        var deniedPaths: [URL] = []
        var notes: [String] = []

        for (offset, child) in children.enumerated() {
            if offset.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            guard Self.supportedExtensions.contains(child.pathExtension.lowercased()) else {
                continue
            }

            do {
                let metadata = try access.metadata(at: child)
                guard !metadata.isSymbolicLink,
                      metadata.isRegularFile || (metadata.isDirectory && metadata.isPackage),
                      let application = Self.matchedApplication(
                        for: child.deletingPathExtension().lastPathComponent,
                        aliases: aliases
                      ) else {
                    continue
                }

                let sizes = try await sizes(for: child, metadata: metadata)
                items.append(ScannedItem(
                    url: child.standardizedFileURL,
                    logicalSize: sizes.logical,
                    allocatedSize: sizes.allocated,
                    creationDate: metadata.creationDate,
                    modificationDate: metadata.modificationDate,
                    resourceIdentifier: metadata.resourceIdentifier,
                    category: .installer,
                    risk: .safe,
                    ownerID: application.id,
                    explanation: "Installer for installed application: \(application.name)"
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                deniedPaths.append(child.standardizedFileURL)
                notes.append("Could not inspect installer package \(child.path): \(error.localizedDescription)")
            }
        }

        return DirectoryScanResult(
            root: root,
            items: items.sorted { $0.url.path < $1.url.path },
            coverage: ScanCoverage(
                deniedPaths: deniedPaths.sorted { $0.path < $1.path },
                notes: notes
            )
        )
    }

    private func sizes(
        for url: URL,
        metadata: FileMetadata
    ) async throws -> (logical: Int64, allocated: Int64) {
        guard metadata.isDirectory else {
            return (metadata.logicalSize, metadata.allocatedSize)
        }

        var pending = [url]
        var logical: Int64 = 0
        var allocated: Int64 = 0
        var visited = 0
        while let directory = pending.popLast() {
            for child in try access.contentsOfDirectory(at: directory) {
                visited += 1
                if visited.isMultiple(of: 128) {
                    try Task.checkCancellation()
                }
                let childMetadata = try access.metadata(at: child)
                guard !childMetadata.isSymbolicLink else { continue }
                if childMetadata.isDirectory {
                    pending.append(child)
                } else if childMetadata.isRegularFile {
                    logical += childMetadata.logicalSize
                    allocated += childMetadata.allocatedSize
                }
            }
        }
        return (logical, allocated)
    }

    private struct ApplicationAlias: Sendable {
        let normalized: String
        let productIdentity: String
        let application: ApplicationRecord
    }

    private static func applicationAliases(
        _ applications: [ApplicationRecord]
    ) -> [ApplicationAlias] {
        applications.flatMap { application -> [ApplicationAlias] in
            var names = [
                application.name,
                application.url.deletingPathExtension().lastPathComponent,
                removingParentheticalSuffix(from: application.name)
            ]
            if let leaf = application.bundleIdentifier?.split(separator: ".").last {
                let value = String(leaf)
                if !genericBundleComponents.contains(value.lowercased()) {
                    names.append(value)
                }
            }
            let identity = application.bundleIdentifier?.lowercased()
                ?? normalized(application.name)
            return Set(names.map(normalized).filter { $0.count >= 4 }).map {
                ApplicationAlias(
                    normalized: $0,
                    productIdentity: identity,
                    application: application
                )
            }
        }
    }

    private static func isInstalledApplication(
        _ application: ApplicationRecord,
        homeDirectory: URL
    ) -> Bool {
        let path = application.url.standardizedFileURL.path
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            homeDirectory.appending(path: "Applications", directoryHint: .isDirectory)
        ].map { $0.standardizedFileURL.path }
        return roots.contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func matchedApplication(
        for installerName: String,
        aliases: [ApplicationAlias]
    ) -> ApplicationRecord? {
        let candidate = normalized(installerName)
        guard !candidate.isEmpty else { return nil }

        let matches = aliases.filter { alias in
            guard candidate.hasPrefix(alias.normalized) else { return false }
            let suffix = String(candidate.dropFirst(alias.normalized.count))
            return suffix.isEmpty || isPermittedInstallerSuffix(suffix)
        }
        let products = Dictionary(grouping: matches, by: \.productIdentity)
        guard products.count == 1, let applications = products.values.first else {
            return nil
        }
        return applications.map(\.application).sorted { lhs, rhs in
            let lhsSystem = lhs.url.path.hasPrefix("/Applications/")
            let rhsSystem = rhs.url.path.hasPrefix("/Applications/")
            if lhsSystem != rhsSystem { return lhsSystem }
            return lhs.url.path < rhs.url.path
        }.first
    }

    private static func isPermittedInstallerSuffix(_ value: String) -> Bool {
        var remainder = value
        while !remainder.isEmpty {
            if remainder.first?.isNumber == true {
                remainder.removeFirst()
                continue
            }
            if remainder.hasPrefix("v"), remainder.dropFirst().first?.isNumber == true {
                remainder.removeFirst()
                continue
            }
            guard let token = permittedSuffixes.first(where: { remainder.hasPrefix($0) }) else {
                return false
            }
            remainder.removeFirst(token.count)
        }
        return true
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        return String(folded.unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func removingParentheticalSuffix(from value: String) -> String {
        guard let index = value.firstIndex(of: "(") else { return value }
        return String(value[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMissingDirectory(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain
            && cocoa.code == NSFileNoSuchFileError
    }
}
