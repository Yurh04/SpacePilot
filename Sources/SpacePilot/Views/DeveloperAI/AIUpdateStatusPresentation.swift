import SpacePilotCore
import SwiftUI

enum AIUpdateStatusPresentation {
    static func result(
        for key: AIUpdateAssetKey,
        in results: [AIUpdateAssetKey: UpdateCheckResult],
        isChecking: Bool
    ) -> UpdateCheckResult? {
        if isChecking, let existing = results[key] {
            return UpdateCheckResult(
                assetKey: existing.assetKey,
                displayName: existing.displayName,
                localVersion: existing.localVersion,
                latestVersion: existing.latestVersion,
                status: .checking,
                checkedAt: existing.checkedAt,
                failure: nil
            )
        }
        return results[key]
    }

    static func statusText(_ result: UpdateCheckResult?) -> String {
        guard let result else { return L10n.text(.aiUpdateStatusUnknown) }
        return switch result.status {
        case .unknown: L10n.text(.aiUpdateStatusUnknown)
        case .unsupported: L10n.text(.aiUpdateStatusUnsupported)
        case .checking: L10n.text(.aiUpdateStatusChecking)
        case .upToDate: L10n.text(.aiUpdateStatusUpToDate)
        case .updateAvailable: L10n.text(.aiUpdateStatusAvailable)
        case .checkFailed: L10n.text(.aiUpdateStatusFailed)
        }
    }

    static func currentVersion(_ result: UpdateCheckResult?, fallback: String?) -> String {
        switch result?.localVersion {
        case .resolved(let evidence): evidence.version
        case .conflict: L10n.text(.aiUpdateEvidenceConflict)
        case .unknown, nil: fallback ?? "—"
        }
    }

    static func latestVersion(_ result: UpdateCheckResult?) -> String {
        result?.latestVersion ?? "—"
    }

    static func evidenceText(_ result: UpdateCheckResult?) -> String {
        guard let result else { return L10n.text(.aiUpdateEvidenceUnknown) }
        switch result.localVersion {
        case .resolved(let evidence):
            return L10n.name(for: evidence.source)
        case .conflict:
            return L10n.text(.aiUpdateEvidenceConflict)
        case .unknown:
            return L10n.text(.aiUpdateEvidenceUnknown)
        }
    }
}

enum AIUpdateKeyBuilder {
    static func key(for application: ApplicationRecord) -> AIUpdateAssetKey {
        AIUpdateAssetKey(
            kind: .application,
            owner: .unknown,
            canonicalLocation: canonical(application.url)
        )
    }

    static func key(for application: AIApplicationRecord) -> AIUpdateAssetKey? {
        guard let applicationURL = application.applicationURL else { return nil }
        return AIUpdateAssetKey(
            kind: .application,
            owner: .unknown,
            canonicalLocation: canonical(applicationURL)
        )
    }

    static func key(for application: AIApplicationJoin.RegistryOnlyApplication) -> AIUpdateAssetKey? {
        guard let applicationURL = application.applicationURL else { return nil }
        return AIUpdateAssetKey(
            kind: .application,
            owner: .unknown,
            canonicalLocation: canonical(applicationURL)
        )
    }

    static func key(for cli: AIToolRecord) -> AIUpdateAssetKey? {
        guard let executableURL = cli.evidence.executableURL else { return nil }
        return AIUpdateAssetKey(
            kind: .cli,
            owner: owner(from: cli.owner),
            canonicalLocation: canonical(executableURL)
        )
    }

    static func key(for skill: SkillRecord) -> AIUpdateAssetKey {
        AIUpdateAssetKey(kind: .skill, owner: skill.owner, canonicalLocation: canonical(skill.url))
    }

    static func key(for plugin: PluginRecord) -> AIUpdateAssetKey {
        AIUpdateAssetKey(kind: .plugin, owner: plugin.owner, canonicalLocation: canonical(plugin.url))
    }

    private static func owner(from owner: AIToolOwner) -> AIAssetOwner {
        switch owner {
        case .tool(let definitionID): .tool(definitionID: definitionID)
        case .shared: .shared
        }
    }

    private static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
