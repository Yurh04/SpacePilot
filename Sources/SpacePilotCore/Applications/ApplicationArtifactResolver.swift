import Foundation

public struct ApplicationArtifactResolution: Sendable {
    public let items: [ScannedItem]
    public let associations: [ArtifactAssociation]

    public init(items: [ScannedItem], associations: [ArtifactAssociation]) {
        self.items = items
        self.associations = associations
    }
}

public struct ApplicationArtifactResolver: Sendable {
    private let roots: [ApplicationArtifactRoot]

    public init(roots: [ApplicationArtifactRoot] = ApplicationArtifactRoot.standard) {
        self.roots = roots
    }

    public func resolve(
        application: ApplicationRecord,
        homeDirectory: URL
    ) async throws -> ApplicationArtifactResolution {
        var items: [ScannedItem] = []
        var associations: [ArtifactAssociation] = []

        for rootRule in roots {
            try Task.checkCancellation()
            let root = homeDirectory.appending(path: rootRule.relativePath, directoryHint: .isDirectory)
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                guard let match = match(child: child, application: application) else { continue }
                let item = ScannedItem(
                    url: child.standardizedFileURL,
                    logicalSize: logicalSize(of: child),
                    allocatedSize: allocatedSize(of: child),
                    modificationDate: (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                    resourceIdentifier: (try? child.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier.map { String(describing: $0) },
                    category: rootRule.category,
                    risk: rootRule.risk,
                    ownerID: application.id,
                    explanation: match.explanation
                )
                items.append(item)
                associations.append(ArtifactAssociation(
                    itemID: item.id,
                    applicationID: application.id,
                    evidence: match.evidence,
                    confidence: match.confidence,
                    risk: rootRule.risk
                ))
            }
        }

        return ApplicationArtifactResolution(items: items, associations: associations)
    }

    private func match(child: URL, application: ApplicationRecord) -> (
        evidence: AssociationEvidence,
        confidence: AssociationConfidence,
        explanation: String
    )? {
        let component = child.lastPathComponent
        let stem = child.deletingPathExtension().lastPathComponent
        if let bundleID = application.bundleIdentifier,
           component == bundleID || stem == bundleID || component.hasPrefix(bundleID + ".") {
            return (.exactBundleIdentifier, .high, "Exact bundle identifier match: \(bundleID)")
        }

        let normalizedName = application.name.lowercased().replacingOccurrences(of: " ", with: "")
        let normalizedComponent = stem.lowercased().replacingOccurrences(of: " ", with: "")
        if normalizedName.count >= 4, normalizedComponent == normalizedName {
            return (.vendorAndNameMatch, .medium, "Application name match in a known service directory")
        }
        return nil
    }

    private func logicalSize(of root: URL) -> Int64 {
        size(of: root, key: .fileSizeKey)
    }

    private func allocatedSize(of root: URL) -> Int64 {
        size(of: root, key: .totalFileAllocatedSizeKey)
    }

    private func size(of root: URL, key: URLResourceKey) -> Int64 {
        let rootValues = try? root.resourceValues(forKeys: [key, .isRegularFileKey])
        if rootValues?.isRegularFile == true {
            return Int64(key == .fileSizeKey ? (rootValues?.fileSize ?? 0) : (rootValues?.totalFileAllocatedSize ?? 0))
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [key, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [key, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(key == .fileSizeKey ? (values.fileSize ?? 0) : (values.totalFileAllocatedSize ?? 0))
        }
        return total
    }
}
