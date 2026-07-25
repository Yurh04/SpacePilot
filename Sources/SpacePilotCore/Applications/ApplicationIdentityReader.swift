import Foundation
import Security

public protocol ApplicationIdentityReading: Sendable {
    func read(application: ApplicationRecord) throws -> ApplicationIdentity
}

public protocol ApplicationSigningMetadataReading: Sendable {
    func metadata(at applicationURL: URL) throws -> ApplicationSigningMetadata
}

public struct SecurityApplicationSigningMetadataReader:
    ApplicationSigningMetadataReading
{
    public init() {}

    public func metadata(at applicationURL: URL) throws -> ApplicationSigningMetadata {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(
            applicationURL as CFURL,
            SecCSFlags(rawValue: 0),
            &staticCode
        )
        guard createStatus == errSecSuccess, let staticCode else {
            throw securityError(status: createStatus)
        }

        var signingInformation: CFDictionary?
        let copyStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard copyStatus == errSecSuccess, let signingInformation else {
            throw securityError(status: copyStatus)
        }

        let information = signingInformation as NSDictionary
        let teamIdentifier = information.object(
            forKey: kSecCodeInfoTeamIdentifier as Any
        ) as? String
        let entitlements = information.object(
            forKey: kSecCodeInfoEntitlementsDict as Any
        ) as? NSDictionary
        let applicationGroups = entitlements?.object(
            forKey: "com.apple.security.application-groups"
        ) as? [String]

        return ApplicationSigningMetadata(
            teamIdentifier: teamIdentifier,
            applicationGroups: Set(applicationGroups ?? [])
        )
    }

    private func securityError(status: OSStatus) -> NSError {
        NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status)
        )
    }
}

public struct ApplicationIdentityReader: ApplicationIdentityReading {
    private let signingReader: any ApplicationSigningMetadataReading
    private let discoveryLimits: ApplicationIdentityDiscoveryLimits

    public init(
        signingReader: any ApplicationSigningMetadataReading =
            SecurityApplicationSigningMetadataReader()
    ) {
        self.signingReader = signingReader
        discoveryLimits = .standard
    }

    init(
        signingReader: any ApplicationSigningMetadataReading,
        discoveryLimits: ApplicationIdentityDiscoveryLimits
    ) {
        self.signingReader = signingReader
        self.discoveryLimits = discoveryLimits
    }

    public func read(application: ApplicationRecord) throws -> ApplicationIdentity {
        try Task.checkCancellation()
        let signingMetadata = try signingReader.metadata(at: application.url)
        return ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: bundleIdentifier(at: application.url),
            componentBundleIdentifiers: try embeddedBundleIdentifiers(
                in: application.url
            ),
            teamIdentifier: signingMetadata.teamIdentifier,
            applicationGroups: signingMetadata.applicationGroups
        )
    }

    private func embeddedBundleIdentifiers(
        in applicationURL: URL
    ) throws -> Set<String> {
        let embeddedBundleDirectories = [
            "Contents/PlugIns",
            "Contents/XPCServices",
            "Contents/Library/LoginItems",
            "Contents/Helpers",
            "Contents/SharedSupport",
            "Contents/Resources",
            "Contents/Frameworks"
        ]
        let canonicalApplicationURL = applicationURL.standardizedFileURL
            .resolvingSymlinksInPath()
        var identifiers = Set<String>()
        var scannedEntryCount = 0

        for relativePath in embeddedBundleDirectories {
            try Task.checkCancellation()
            let directoryURL = applicationURL.appending(
                path: relativePath,
                directoryHint: .isDirectory
            )
            guard let canonicalDirectoryURL = safeDirectory(
                at: directoryURL,
                strictlyWithin: canonicalApplicationURL
            ) else {
                continue
            }
            try discoverBundleIdentifiers(
                below: canonicalDirectoryURL,
                applicationRoot: canonicalApplicationURL,
                scannedEntryCount: &scannedEntryCount,
                identifiers: &identifiers
            )
            if scannedEntryCount >= discoveryLimits.maximumScannedEntries {
                break
            }
        }

        return identifiers
    }

    private func discoverBundleIdentifiers(
        below root: URL,
        applicationRoot: URL,
        scannedEntryCount: inout Int,
        identifiers: inout Set<String>
    ) throws {
        var pending: [(url: URL, depth: Int)] = [(root, 0)]
        var nextIndex = 0
        let supportedBundleExtensions: Set<String> = [
            "app", "appex", "xpc", "bundle"
        ]

        while nextIndex < pending.count,
              scannedEntryCount < discoveryLimits.maximumScannedEntries {
            try Task.checkCancellation()
            let directory = pending[nextIndex]
            nextIndex += 1
            guard directory.depth < discoveryLimits.maximumDepth,
                  let children = try? FileManager.default.contentsOfDirectory(
                    at: directory.url,
                    includingPropertiesForKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey
                    ],
                    options: [.skipsHiddenFiles]
                  )
            else {
                continue
            }

            for child in children.sorted(by: { $0.path < $1.path }) {
                try Task.checkCancellation()
                guard scannedEntryCount
                        < discoveryLimits.maximumScannedEntries
                else {
                    return
                }
                scannedEntryCount += 1

                guard let canonicalChild = safeDirectory(
                    at: child,
                    strictlyWithin: applicationRoot
                ) else {
                    continue
                }

                if supportedBundleExtensions.contains(
                    child.pathExtension.lowercased()
                ) {
                    if let identifier = bundleIdentifier(at: canonicalChild) {
                        identifiers.insert(identifier)
                    }
                    // A component bundle is an ownership boundary. Its contents
                    // are intentionally not traversed as part of the parent app.
                    continue
                }

                pending.append((
                    url: canonicalChild,
                    depth: directory.depth + 1
                ))
            }
        }
    }

    private func safeDirectory(
        at url: URL,
        strictlyWithin root: URL
    ) -> URL? {
        guard let values = try? url.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ), values.isDirectory == true, values.isSymbolicLink != true
        else {
            return nil
        }

        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isStrictDescendant(canonicalURL, of: root) else {
            return nil
        }
        return canonicalURL
    }

    private func isStrictDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && candidateComponents.starts(with: rootComponents)
    }

    private func bundleIdentifier(at bundleURL: URL) -> String? {
        let canonicalBundleURL = bundleURL.standardizedFileURL
            .resolvingSymlinksInPath()
        let infoURLs = [
            bundleURL.appending(path: "Contents/Info.plist"),
            bundleURL.appending(path: "Info.plist")
        ]
        for infoURL in infoURLs {
            guard let canonicalInfoURL = safeRegularFile(
                at: infoURL,
                strictlyWithin: canonicalBundleURL
            ),
                  let data = try? Data(contentsOf: canonicalInfoURL),
                  let info = try? PropertyListSerialization.propertyList(
                    from: data,
                    format: nil
                  ) as? [String: Any],
                  let identifier = info["CFBundleIdentifier"] as? String,
                  !identifier.isEmpty
            else {
                continue
            }
            return identifier
        }
        return nil
    }

    private func safeRegularFile(
        at url: URL,
        strictlyWithin root: URL
    ) -> URL? {
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ), values.isRegularFile == true, values.isSymbolicLink != true
        else {
            return nil
        }

        let canonicalURL = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isStrictDescendant(canonicalURL, of: root) else {
            return nil
        }
        return canonicalURL
    }
}
