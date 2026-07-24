import Foundation

public protocol ScanResultCaching: Sendable {
    func cachedApplicationInventory(
        at location: URL
    ) async throws -> [ApplicationRecord]?

    func save(
        applicationInventory: [ApplicationRecord],
        at location: URL
    ) async throws

    func cachedApplicationIdentity(
        for application: ApplicationRecord
    ) async throws -> ApplicationIdentity?

    func save(
        applicationIdentity: ApplicationIdentity,
        for application: ApplicationRecord
    ) async throws

    func cachedAIApplicationScan(
        key: String,
        root: URL
    ) async throws -> AIApplicationScanResult?

    func save(
        aiApplicationScan: AIApplicationScanResult,
        key: String,
        root: URL
    ) async throws
}

extension SQLiteIndexStore: ScanResultCaching {}

enum ScanCacheValidation {
    static func token(for url: URL) -> String {
        guard let values = try? url.resourceValues(forKeys: [
            .fileResourceIdentifierKey,
            .contentModificationDateKey,
            .isDirectoryKey
        ]) else {
            return "missing"
        }
        let identifier = values.fileResourceIdentifier.map {
            String(describing: $0)
        } ?? ""
        let modified = values.contentModificationDate?
            .timeIntervalSince1970.description ?? ""
        return [
            values.isDirectory == true ? "directory" : "file",
            identifier,
            modified
        ].joined(separator: "|")
    }

    static func token(for application: ApplicationRecord) -> String {
        [
            token(for: application.url),
            application.bundleIdentifier ?? "",
            application.version ?? "",
            String(application.allocatedSize)
        ].joined(separator: "|")
    }

    static func applicationInventoryToken(at location: URL) -> String {
        guard let candidates = try? FileManager.default.contentsOfDirectory(
            at: location,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileResourceIdentifierKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return "missing"
        }
        return candidates
            .filter { $0.pathExtension.lowercased() == "app" }
            .map { application in
                let values = try? application.resourceValues(forKeys: [
                    .contentModificationDateKey,
                    .fileResourceIdentifierKey
                ])
                let infoModified = (try? application.appending(
                    path: "Contents/Info.plist"
                ).resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate)?
                    .timeIntervalSince1970.description ?? ""
                let signatureModified = (try? application.appending(
                    path: "Contents/_CodeSignature/CodeResources"
                ).resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate)?
                    .timeIntervalSince1970.description ?? ""
                return [
                    application.lastPathComponent,
                    values?.fileResourceIdentifier.map {
                        String(describing: $0)
                    } ?? "",
                    values?.contentModificationDate?
                        .timeIntervalSince1970.description ?? "",
                    infoModified,
                    signatureModified
                ].joined(separator: "|")
            }
            .sorted()
            .joined(separator: "\n")
    }
}
