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

    public init(
        signingReader: any ApplicationSigningMetadataReading =
            SecurityApplicationSigningMetadataReader()
    ) {
        self.signingReader = signingReader
    }

    public func read(application: ApplicationRecord) throws -> ApplicationIdentity {
        let signingMetadata = try signingReader.metadata(at: application.url)
        return ApplicationIdentity(
            applicationID: application.id,
            mainBundleIdentifier: bundleIdentifier(at: application.url),
            componentBundleIdentifiers: embeddedBundleIdentifiers(
                in: application.url
            ),
            teamIdentifier: signingMetadata.teamIdentifier,
            applicationGroups: signingMetadata.applicationGroups
        )
    }

    private func embeddedBundleIdentifiers(in applicationURL: URL) -> Set<String> {
        let embeddedBundleDirectories = [
            "Contents/PlugIns",
            "Contents/XPCServices",
            "Contents/Library/LoginItems",
            "Contents/Helpers"
        ]
        var identifiers = Set<String>()

        for relativePath in embeddedBundleDirectories {
            let directoryURL = applicationURL.appending(
                path: relativePath,
                directoryHint: .isDirectory
            )
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for child in children {
                guard ["app", "appex", "xpc"].contains(
                    child.pathExtension.lowercased()
                ) else {
                    continue
                }
                if let identifier = bundleIdentifier(at: child) {
                    identifiers.insert(identifier)
                }
            }
        }

        return identifiers
    }

    private func bundleIdentifier(at bundleURL: URL) -> String? {
        let infoURL = bundleURL.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let info = try? PropertyListSerialization.propertyList(
                from: data,
                format: nil
              ) as? [String: Any]
        else {
            return nil
        }
        return info["CFBundleIdentifier"] as? String
    }
}
