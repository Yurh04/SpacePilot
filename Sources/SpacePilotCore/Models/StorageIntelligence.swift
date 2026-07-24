import Foundation

public enum StorageOwnerType: String, Codable, Sendable {
    case application
    case aiAgent
    case developerTool
    case shared
    case system
}

public enum IndexedResourceKind: String, Codable, Sendable {
    case file
    case directory
    case applicationBundle
    case plugin
    case skill
}

public enum IndexedResourceState: String, Codable, Sendable {
    case current
    case dirty
    case missing
}

public enum StorageResourceRole: String, Codable, Sendable {
    case application
    case data
    case cache
    case log
    case conversation
    case model
    case plugin
    case skill
    case developerData
    case systemData
    case unknown
}

public struct StorageOwner: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let type: StorageOwnerType
    public let identifier: String
    public let displayName: String

    public init(
        id: String,
        type: StorageOwnerType,
        identifier: String,
        displayName: String
    ) {
        self.id = id
        self.type = type
        self.identifier = identifier
        self.displayName = displayName
    }
}

public struct IndexedStorageResource: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let url: URL
    public let kind: IndexedResourceKind
    public let logicalSize: Int64
    public let allocatedSize: Int64
    public let modificationDate: Date?
    public let resourceIdentifier: String?
    public let category: ItemCategory
    public let risk: RiskLevel
    public let state: IndexedResourceState
    public let indexedAt: Date

    public init(
        id: String,
        url: URL,
        kind: IndexedResourceKind,
        logicalSize: Int64,
        allocatedSize: Int64,
        modificationDate: Date?,
        resourceIdentifier: String?,
        category: ItemCategory,
        risk: RiskLevel,
        state: IndexedResourceState = .current,
        indexedAt: Date
    ) {
        self.id = id
        self.url = url
        self.kind = kind
        self.logicalSize = max(0, logicalSize)
        self.allocatedSize = max(0, allocatedSize)
        self.modificationDate = modificationDate
        self.resourceIdentifier = resourceIdentifier
        self.category = category
        self.risk = risk
        self.state = state
        self.indexedAt = indexedAt
    }
}

public struct StorageOwnership: Codable, Hashable, Sendable {
    public let resourceID: String
    public let ownerID: String
    public let role: StorageResourceRole
    public let confidence: Int
    public let reason: String

    public init(
        resourceID: String,
        ownerID: String,
        role: StorageResourceRole,
        confidence: Int,
        reason: String
    ) {
        self.resourceID = resourceID
        self.ownerID = ownerID
        self.role = role
        self.confidence = min(100, max(0, confidence))
        self.reason = reason
    }
}

public struct DirectoryStat: Codable, Hashable, Sendable {
    public let resourceID: String
    public let totalLogicalSize: Int64
    public let totalAllocatedSize: Int64
    public let fileCount: Int?
    public let directoryCount: Int?
    public let indexedAt: Date
    public let isDirty: Bool

    public init(
        resourceID: String,
        totalLogicalSize: Int64,
        totalAllocatedSize: Int64,
        fileCount: Int? = nil,
        directoryCount: Int? = nil,
        indexedAt: Date,
        isDirty: Bool = false
    ) {
        self.resourceID = resourceID
        self.totalLogicalSize = max(0, totalLogicalSize)
        self.totalAllocatedSize = max(0, totalAllocatedSize)
        self.fileCount = fileCount
        self.directoryCount = directoryCount
        self.indexedAt = indexedAt
        self.isDirty = isDirty
    }
}

public struct StorageIndexSummary: Codable, Hashable, Sendable {
    public let ownerCount: Int
    public let resourceCount: Int
    public let ownershipCount: Int
    public let directoryStatCount: Int
    public let allocatedSize: Int64
    public let lastUpdatedAt: Date?

    public init(
        ownerCount: Int,
        resourceCount: Int,
        ownershipCount: Int,
        directoryStatCount: Int,
        allocatedSize: Int64,
        lastUpdatedAt: Date?
    ) {
        self.ownerCount = ownerCount
        self.resourceCount = resourceCount
        self.ownershipCount = ownershipCount
        self.directoryStatCount = directoryStatCount
        self.allocatedSize = max(0, allocatedSize)
        self.lastUpdatedAt = lastUpdatedAt
    }
}

struct StorageIntelligenceGraph: Sendable {
    let owners: [StorageOwner]
    let resources: [IndexedStorageResource]
    let ownerships: [StorageOwnership]
    let directoryStats: [DirectoryStat]

    init(snapshot: ScanSnapshot) {
        var ownersByID: [String: StorageOwner] = [:]
        var resourcesByID: [String: IndexedStorageResource] = [:]
        var ownershipsByKey: [String: StorageOwnership] = [:]
        var itemResourceIDs: [UUID: String] = [:]
        var applicationOwnerIDs: [UUID: String] = [:]
        var aiOwnerIDs: [UUID: String] = [:]
        let itemsByID = Dictionary(
            uniqueKeysWithValues: snapshot.items.map { ($0.id, $0) }
        )

        func ownerID(prefix: String, identifier: String) -> String {
            prefix + ":" + identifier.lowercased()
        }

        func resourceID(for url: URL) -> String {
            url.standardizedFileURL.path
        }

        func addOwner(_ owner: StorageOwner) {
            ownersByID[owner.id] = owner
        }

        func addResource(_ resource: IndexedStorageResource) {
            if let existing = resourcesByID[resource.id],
               existing.kind != .file,
               resource.kind == .file {
                return
            }
            resourcesByID[resource.id] = resource
        }

        func addOwnership(_ ownership: StorageOwnership) {
            let key = [
                ownership.resourceID,
                ownership.ownerID,
                ownership.role.rawValue
            ].joined(separator: "\u{1f}")
            if let existing = ownershipsByKey[key],
               existing.confidence >= ownership.confidence {
                return
            }
            ownershipsByKey[key] = ownership
        }

        for item in snapshot.items {
            let id = resourceID(for: item.url)
            itemResourceIDs[item.id] = id
            addResource(IndexedStorageResource(
                id: id,
                url: item.url.standardizedFileURL,
                kind: item.url.hasDirectoryPath ? .directory : .file,
                logicalSize: item.logicalSize,
                allocatedSize: item.allocatedSize,
                modificationDate: item.modificationDate,
                resourceIdentifier: item.resourceIdentifier,
                category: item.category,
                risk: item.risk,
                indexedAt: snapshot.completedAt
            ))
        }

        for application in snapshot.applications {
            let identifier = application.bundleIdentifier
                ?? application.url.standardizedFileURL.path
            let id = ownerID(prefix: "app", identifier: identifier)
            applicationOwnerIDs[application.id] = id
            addOwner(StorageOwner(
                id: id,
                type: .application,
                identifier: identifier,
                displayName: application.name
            ))
            let applicationResourceID = resourceID(for: application.url)
            addResource(IndexedStorageResource(
                id: applicationResourceID,
                url: application.url.standardizedFileURL,
                kind: .applicationBundle,
                logicalSize: application.allocatedSize,
                allocatedSize: application.allocatedSize,
                modificationDate: application.lastUsedDate,
                resourceIdentifier: nil,
                category: .application,
                risk: .rebuildable,
                indexedAt: snapshot.completedAt
            ))
            addOwnership(StorageOwnership(
                resourceID: applicationResourceID,
                ownerID: id,
                role: .application,
                confidence: 100,
                reason: "Installed application bundle"
            ))
        }

        for application in snapshot.applications {
            guard let ownerID = applicationOwnerIDs[application.id] else { continue }
            for association in application.associations {
                guard let resourceID = itemResourceIDs[association.itemID],
                      let item = itemsByID[association.itemID] else {
                    continue
                }
                addOwnership(StorageOwnership(
                    resourceID: resourceID,
                    ownerID: ownerID,
                    role: Self.role(for: item.category),
                    confidence: association.confidence.rawValue,
                    reason: association.evidence.rawValue
                ))
            }
        }

        for application in snapshot.aiApplications {
            let identifier = application.bundleIdentifier ?? application.name
            let id = ownerID(prefix: "ai", identifier: identifier)
            aiOwnerIDs[application.id] = id
            addOwner(StorageOwner(
                id: id,
                type: .aiAgent,
                identifier: identifier,
                displayName: application.name
            ))
            for itemID in application.itemIDs {
                guard let resourceID = itemResourceIDs[itemID],
                      let item = itemsByID[itemID] else {
                    continue
                }
                addOwnership(StorageOwnership(
                    resourceID: resourceID,
                    ownerID: id,
                    role: Self.role(for: item.category),
                    confidence: application.supportLevel == .deep ? 100 : 90,
                    reason: application.supportLevel == .deep
                        ? "Deep AI application rule"
                        : "Recognized AI application data root"
                ))
            }
            if let applicationURL = application.applicationURL {
                let applicationResourceID = resourceID(for: applicationURL)
                if resourcesByID[applicationResourceID] != nil {
                    addOwnership(StorageOwnership(
                        resourceID: applicationResourceID,
                        ownerID: id,
                        role: .application,
                        confidence: 100,
                        reason: "AI application bundle"
                    ))
                }
            }
        }

        let pluginResourceIDs = Dictionary(
            uniqueKeysWithValues: snapshot.plugins.map {
                ($0.id, resourceID(for: $0.url))
            }
        )
        let skillResourceIDs = Dictionary(
            uniqueKeysWithValues: snapshot.skills.map {
                ($0.id, resourceID(for: $0.url))
            }
        )
        for plugin in snapshot.plugins {
            let id = resourceID(for: plugin.url)
            addResource(IndexedStorageResource(
                id: id,
                url: plugin.url.standardizedFileURL,
                kind: .plugin,
                logicalSize: plugin.allocatedSize,
                allocatedSize: plugin.allocatedSize,
                modificationDate: nil,
                resourceIdentifier: nil,
                category: .plugin,
                risk: .managed,
                indexedAt: snapshot.completedAt
            ))
        }
        for skill in snapshot.skills {
            let id = resourceID(for: skill.url)
            addResource(IndexedStorageResource(
                id: id,
                url: skill.url.standardizedFileURL,
                kind: .skill,
                logicalSize: skill.allocatedSize,
                allocatedSize: skill.allocatedSize,
                modificationDate: nil,
                resourceIdentifier: nil,
                category: .skill,
                risk: skill.managementStatus == .standalone ? .sensitive : .managed,
                indexedAt: snapshot.completedAt
            ))
        }

        for application in snapshot.aiApplications {
            guard let ownerID = aiOwnerIDs[application.id] else { continue }
            for pluginID in application.pluginIDs {
                guard let resourceID = pluginResourceIDs[pluginID] else { continue }
                addOwnership(StorageOwnership(
                    resourceID: resourceID,
                    ownerID: ownerID,
                    role: .plugin,
                    confidence: 100,
                    reason: "Plugin installed for AI application"
                ))
            }
            for skillID in application.skillIDs {
                guard let resourceID = skillResourceIDs[skillID] else { continue }
                addOwnership(StorageOwnership(
                    resourceID: resourceID,
                    ownerID: ownerID,
                    role: .skill,
                    confidence: 100,
                    reason: "Skill visible to AI application"
                ))
            }
        }

        let sharedOwner = StorageOwner(
            id: "shared:agent-assets",
            type: .shared,
            identifier: "agent-assets",
            displayName: "Shared Agent Assets"
        )
        let developerOwner = StorageOwner(
            id: "developer:tooling",
            type: .developerTool,
            identifier: "tooling",
            displayName: "Development Tools"
        )
        let systemOwner = StorageOwner(
            id: "system:macos",
            type: .system,
            identifier: "macos",
            displayName: "macOS"
        )

        let ownedResourceIDs = Set(ownershipsByKey.values.map(\.resourceID))
        for resource in resourcesByID.values where !ownedResourceIDs.contains(resource.id) {
            let owner: StorageOwner?
            switch resource.category {
            case .developer:
                owner = developerOwner
            case .plugin, .skill:
                owner = sharedOwner
            case .system:
                owner = systemOwner
            default:
                owner = nil
            }
            guard let owner else { continue }
            addOwner(owner)
            addOwnership(StorageOwnership(
                resourceID: resource.id,
                ownerID: owner.id,
                role: Self.role(for: resource.category),
                confidence: 80,
                reason: "Category ownership fallback"
            ))
        }

        owners = ownersByID.values.sorted { $0.id < $1.id }
        resources = resourcesByID.values.sorted { $0.id < $1.id }
        ownerships = ownershipsByKey.values.sorted {
            if $0.ownerID != $1.ownerID { return $0.ownerID < $1.ownerID }
            if $0.resourceID != $1.resourceID {
                return $0.resourceID < $1.resourceID
            }
            return $0.role.rawValue < $1.role.rawValue
        }
        directoryStats = resources.compactMap { resource in
            guard resource.kind != .file else { return nil }
            return DirectoryStat(
                resourceID: resource.id,
                totalLogicalSize: resource.logicalSize,
                totalAllocatedSize: resource.allocatedSize,
                indexedAt: resource.indexedAt
            )
        }
    }

    private static func role(for category: ItemCategory) -> StorageResourceRole {
        switch category {
        case .application: .application
        case .cache: .cache
        case .log: .log
        case .conversation: .conversation
        case .model: .model
        case .plugin: .plugin
        case .skill: .skill
        case .developer: .developerData
        case .system: .systemData
        case .aiData: .data
        case .personal, .unclassified: .unknown
        }
    }
}
