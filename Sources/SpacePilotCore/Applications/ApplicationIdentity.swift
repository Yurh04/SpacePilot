import Foundation

public struct ApplicationIdentity: Sendable {
    public let applicationID: UUID
    public let mainBundleIdentifier: String?
    public let componentBundleIdentifiers: Set<String>
    public let teamIdentifier: String?
    public let applicationGroups: Set<String>

    public init(
        applicationID: UUID,
        mainBundleIdentifier: String?,
        componentBundleIdentifiers: Set<String>,
        teamIdentifier: String?,
        applicationGroups: Set<String>
    ) {
        self.applicationID = applicationID
        self.mainBundleIdentifier = mainBundleIdentifier
        self.componentBundleIdentifiers = componentBundleIdentifiers
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }

    public var allBundleIdentifiers: Set<String> {
        var result = componentBundleIdentifiers
        if let mainBundleIdentifier {
            result.insert(mainBundleIdentifier)
        }
        return result
    }
}

public struct ApplicationSigningMetadata: Sendable {
    public let teamIdentifier: String?
    public let applicationGroups: Set<String>

    public init(
        teamIdentifier: String?,
        applicationGroups: Set<String>
    ) {
        self.teamIdentifier = teamIdentifier
        self.applicationGroups = applicationGroups
    }
}
