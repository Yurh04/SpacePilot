import Foundation

public struct FileMetadata: Sendable {
    public let isDirectory: Bool
    public let isRegularFile: Bool
    public let isSymbolicLink: Bool
    public let isPackage: Bool
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let creationDate: Date?
    public let modificationDate: Date?
    public let resourceIdentifier: String?

    public init(
        isDirectory: Bool,
        isRegularFile: Bool,
        isSymbolicLink: Bool,
        isPackage: Bool,
        logicalSize: Int64,
        allocatedSize: Int64,
        creationDate: Date?,
        modificationDate: Date?,
        resourceIdentifier: String?
    ) {
        self.isDirectory = isDirectory
        self.isRegularFile = isRegularFile
        self.isSymbolicLink = isSymbolicLink
        self.isPackage = isPackage
        self.logicalSize = logicalSize
        self.allocatedSize = allocatedSize
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.resourceIdentifier = resourceIdentifier
    }
}

public protocol FileSystemAccess: Sendable {
    func metadata(at url: URL) throws -> FileMetadata
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

public struct LocalFileSystemAccess: FileSystemAccess {
    private static let metadataKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .fileSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .fileResourceIdentifierKey
    ]

    public init() {}

    public func metadata(at url: URL) throws -> FileMetadata {
        let values = try url.resourceValues(forKeys: Self.metadataKeys)
        return FileMetadata(
            isDirectory: values.isDirectory == true,
            isRegularFile: values.isRegularFile == true,
            isSymbolicLink: values.isSymbolicLink == true,
            isPackage: values.isPackage == true,
            logicalSize: Int64(values.fileSize ?? 0),
            allocatedSize: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate,
            resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    public func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: Array(Self.metadataKeys),
            options: []
        )
    }
}
