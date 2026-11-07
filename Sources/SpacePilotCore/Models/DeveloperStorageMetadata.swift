import Foundation

public enum DeveloperStorageItemKind: String, Codable, Sendable {
    case toolCache
    case simulatorDevice
    case simulatorRuntime
}

/// Structured metadata used by the developer-storage page. Simulator names,
/// states and dates are metadata only; SpacePilot never reads simulator app
/// data or runtime contents to build these labels.
public struct DeveloperStorageMetadata: Codable, Hashable, Sendable {
    public let kind: DeveloperStorageItemKind
    public let name: String
    public let runtimeIdentifier: String?
    public let runtimeVersion: String?
    public let buildVersion: String?
    public let state: String?
    public let lastUsedDate: Date?
    public let isAvailable: Bool?
    public let isInUse: Bool?

    public init(
        kind: DeveloperStorageItemKind,
        name: String,
        runtimeIdentifier: String? = nil,
        runtimeVersion: String? = nil,
        buildVersion: String? = nil,
        state: String? = nil,
        lastUsedDate: Date? = nil,
        isAvailable: Bool? = nil,
        isInUse: Bool? = nil
    ) {
        self.kind = kind
        self.name = name
        self.runtimeIdentifier = runtimeIdentifier
        self.runtimeVersion = runtimeVersion
        self.buildVersion = buildVersion
        self.state = state
        self.lastUsedDate = lastUsedDate
        self.isAvailable = isAvailable
        self.isInUse = isInUse
    }
}
