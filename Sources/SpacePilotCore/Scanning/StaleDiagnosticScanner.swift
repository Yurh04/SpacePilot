import Foundation

public struct StaleDiagnosticScanResult: Sendable {
    public let items: [ScannedItem]
    public let coverage: ScanCoverage

    public init(items: [ScannedItem], coverage: ScanCoverage) {
        self.items = items
        self.coverage = coverage
    }
}

/// Finds individual, stale diagnostic files under a small set of explicit
/// user-owned log roots. The scanner reads metadata only and never opens log
/// contents. Returning files rather than directories lets cleanup revalidate
/// size, modification date, and file identity immediately before moving them.
public struct StaleDiagnosticScanner<Access: FileSystemAccess>: Sendable {
    public static var explanation: String {
        "Diagnostic log or crash report older than 30 days"
    }

    public static var defaultMinimumAge: TimeInterval {
        30 * 24 * 60 * 60
    }

    private static var relativeRoots: [String] {
        [
            "Library/Logs",
            ".npm/_logs",
            ".codex/logs",
            ".claude/debug"
        ]
    }

    private let access: Access
    private let minimumAge: TimeInterval
    private let retainedItemLimit: Int
    private let now: @Sendable () -> Date

    public init(
        access: Access,
        minimumAge: TimeInterval = Self.defaultMinimumAge,
        retainedItemLimit: Int = 2_000,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.access = access
        self.minimumAge = max(0, minimumAge)
        self.retainedItemLimit = max(0, retainedItemLimit)
        self.now = now
    }

    public func scan(homeDirectory: URL) async throws -> StaleDiagnosticScanResult {
        let cutoff = now().addingTimeInterval(-minimumAge)
        var selection = StaleDiagnosticSelection(limit: retainedItemLimit)
        var deniedPaths: [URL] = []
        var notes: [String] = []
        var visited = 0

        for relativeRoot in Self.relativeRoots {
            try Task.checkCancellation()
            let root = homeDirectory.appending(
                path: relativeRoot,
                directoryHint: .isDirectory
            ).standardizedFileURL
            let rootMetadata: FileMetadata
            do {
                rootMetadata = try access.metadata(at: root)
            } catch {
                if Self.isMissing(error) { continue }
                deniedPaths.append(root)
                notes.append(
                    "Could not inspect diagnostic root \(root.path): "
                        + error.localizedDescription
                )
                continue
            }
            guard rootMetadata.isDirectory, !rootMetadata.isSymbolicLink else {
                continue
            }

            var pending = [root]
            while let directory = pending.popLast() {
                let children: [URL]
                do {
                    children = try access.contentsOfDirectory(at: directory)
                } catch {
                    deniedPaths.append(directory.standardizedFileURL)
                    notes.append(
                        "Could not read diagnostic directory \(directory.path): "
                            + error.localizedDescription
                    )
                    continue
                }

                for child in children {
                    visited += 1
                    if visited.isMultiple(of: 128) {
                        try Task.checkCancellation()
                    }
                    do {
                        let metadata = try access.metadata(at: child)
                        guard !metadata.isSymbolicLink else { continue }
                        if metadata.isDirectory {
                            if !metadata.isPackage {
                                pending.append(child.standardizedFileURL)
                            }
                            continue
                        }
                        guard metadata.isRegularFile,
                              metadata.allocatedSize > 0,
                              let lastModified = metadata.modificationDate
                                ?? metadata.creationDate,
                              lastModified <= cutoff else {
                            continue
                        }
                        selection.insert(ScannedItem(
                            url: child.standardizedFileURL,
                            logicalSize: metadata.logicalSize,
                            allocatedSize: metadata.allocatedSize,
                            creationDate: metadata.creationDate,
                            modificationDate: metadata.modificationDate,
                            resourceIdentifier: metadata.resourceIdentifier,
                            category: .log,
                            risk: .safe,
                            explanation: Self.explanation
                        ))
                    } catch {
                        deniedPaths.append(child.standardizedFileURL)
                        notes.append(
                            "Could not inspect diagnostic item \(child.path): "
                                + error.localizedDescription
                        )
                    }
                }
            }
        }

        try Task.checkCancellation()
        return StaleDiagnosticScanResult(
            items: selection.items.sorted { $0.url.path < $1.url.path },
            coverage: ScanCoverage(
                deniedPaths: Dictionary(
                    deniedPaths.map { ($0.path, $0) },
                    uniquingKeysWith: { first, _ in first }
                ).values.sorted { $0.path < $1.path },
                notes: Array(Set(notes)).sorted()
            )
        )
    }

    private static func isMissing(_ error: Error) -> Bool {
        guard let cocoaError = error as? CocoaError else { return false }
        return cocoaError.code == .fileNoSuchFile
            || cocoaError.code == .fileReadNoSuchFile
    }
}

private struct StaleDiagnosticSelection {
    let limit: Int
    private var values: [ScannedItem] = []

    init(limit: Int) {
        self.limit = limit
    }

    var items: [ScannedItem] { values }

    mutating func insert(_ item: ScannedItem) {
        guard limit > 0 else { return }
        if values.count < limit {
            values.append(item)
            return
        }
        guard let smallestIndex = values.indices.min(by: {
            values[$0].allocatedSize < values[$1].allocatedSize
        }), item.allocatedSize > values[smallestIndex].allocatedSize else {
            return
        }
        values[smallestIndex] = item
    }
}
