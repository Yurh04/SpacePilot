import CoreServices
import Foundation

public struct ApplicationScanner: Sendable {
    private let cache: (any ScanResultCaching)?
    private let supplementaryApplicationURLs: @Sendable () -> [URL]

    public init(
        cache: (any ScanResultCaching)? = nil,
        supplementaryApplicationURLs: @escaping @Sendable () -> [URL] = { [] }
    ) {
        self.cache = cache
        self.supplementaryApplicationURLs = supplementaryApplicationURLs
    }

    public func scan(locations: [URL]) async throws -> [ApplicationRecord] {
        var seen = Set<String>()
        var records: [ApplicationRecord] = []

        for location in locations {
            let locationRecords: [ApplicationRecord]
            let cached: [ApplicationRecord]?
            if let cache {
                cached = try? await cache.cachedApplicationInventory(
                    at: location
                )
            } else {
                cached = nil
            }
            if let cached {
                locationRecords = cached.map(refreshVolatileMetadata)
            } else {
                locationRecords = try scan(location: location)
                if let cache {
                    try? await cache.save(
                        applicationInventory: locationRecords,
                        at: location
                    )
                }
            }
            for record in locationRecords {
                let canonical = record.url.standardizedFileURL
                    .resolvingSymlinksInPath()
                guard seen.insert(canonical.path).inserted else { continue }
                records.append(record)
            }
        }

        var primaryBundleIdentifiers = Set(
            records.compactMap(\.bundleIdentifier).map { $0.lowercased() }
        )
        for candidate in supplementaryApplicationURLs() {
            try Task.checkCancellation()
            let canonical = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard seen.insert(canonical.path).inserted,
                  let record = try makeRecord(at: canonical)
            else { continue }
            if let bundleIdentifier = record.bundleIdentifier?.lowercased(),
               !primaryBundleIdentifiers.insert(bundleIdentifier).inserted {
                continue
            }
            records.append(record)
        }

        return records.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func scan(location: URL) throws -> [ApplicationRecord] {
        let candidates = try ApplicationBundleLocator.applicationURLs(in: location)
        var records: [ApplicationRecord] = []
        for candidate in candidates {
            try Task.checkCancellation()
            let canonical = candidate.standardizedFileURL
                .resolvingSymlinksInPath()
            if let record = try makeRecord(at: canonical) {
                records.append(record)
            }
        }
        return records
    }

    private func makeRecord(at appURL: URL) throws -> ApplicationRecord? {
        let infoURL = appURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let name = [
            info["CFBundleDisplayName"] as? String,
            info["CFBundleName"] as? String
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
            ?? appURL.deletingPathExtension().lastPathComponent
        let executableName = info["CFBundleExecutable"] as? String
        let executableURL = executableName.map { appURL.appending(path: "Contents/MacOS/\($0)") }
        let lastUsedDate = (try? appURL.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate

        return ApplicationRecord(
            name: name,
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            version: (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String),
            url: appURL,
            executableURL: executableURL,
            allocatedSize: allocatedSize(of: appURL),
            lastUsedDate: lastUsedDate
        )
    }

    private func refreshVolatileMetadata(
        _ record: ApplicationRecord
    ) -> ApplicationRecord {
        let lastUsedDate = (try? record.url.resourceValues(
            forKeys: [.contentAccessDateKey]
        ))?.contentAccessDate ?? record.lastUsedDate
        return ApplicationRecord(
            id: record.id,
            name: record.name,
            bundleIdentifier: record.bundleIdentifier,
            version: record.version,
            url: record.url,
            executableURL: record.executableURL,
            allocatedSize: record.allocatedSize,
            lastUsedDate: lastUsedDate,
            associations: record.associations
        )
    }

    private func allocatedSize(of root: URL) -> Int64 {
        if let metadataItem = MDItemCreate(
            kCFAllocatorDefault,
            root.path as CFString
        ), let size = MDItemCopyAttribute(
            metadataItem,
            "kMDItemPhysicalSize" as CFString
        ) as? NSNumber, size.int64Value > 0 {
            return size.int64Value
        }

        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
