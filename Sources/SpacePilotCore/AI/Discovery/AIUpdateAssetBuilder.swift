import Foundation

public struct AIUpdateAssetInventory: Sendable, Equatable {
    public let assets: [AIUpdateAsset]
    public let unsupportedResults: [UpdateCheckResult]
    /// Fixed, code-owned execution capabilities keyed by the asset key they
    /// apply to. Populated only for assets whose definition declares a
    /// `updateExecutionCapability`; everything else is absent (handoff only).
    public let executionCapabilities: [AIUpdateAssetKey: UpdateExecutionCapability]

    public init(
        assets: [AIUpdateAsset],
        unsupportedResults: [UpdateCheckResult],
        executionCapabilities: [AIUpdateAssetKey: UpdateExecutionCapability] = [:]
    ) {
        self.assets = assets
        self.unsupportedResults = unsupportedResults
        self.executionCapabilities = executionCapabilities
    }
}

public enum AIUpdateAssetBuilder {
    public static func inventory(
        snapshot: ScanSnapshot?,
        managementProjection: AIManagementProjection,
        projectSkills: [SkillRecord],
        projectPlugins: [PluginRecord],
        packageFacts: [AIToolPackageInstallFact] = [],
        definitions: [AIToolDefinition] = KnownAIToolDefinitions.all
    ) -> AIUpdateAssetInventory {
        let definitionByID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        var assets: [AIUpdateAsset] = []
        var unsupported: [UpdateCheckResult] = []
        var executionCapabilities: [AIUpdateAssetKey: UpdateExecutionCapability] = [:]
        var seen = Set<AIUpdateAssetKey>()

        func append(_ asset: AIUpdateAsset, executionDefinitionID: String? = nil) {
            guard seen.insert(asset.key).inserted else { return }
            assets.append(asset)
            if asset.capability == nil {
                unsupported.append(.unsupported(asset: asset))
            }
            // Execution capability is attached only from the fixed definition
            // table, never from a receipt/manifest, and only when the check
            // provider's package identifier matches the execution package so the
            // version we checked is the one we would install.
            if let executionDefinitionID,
               let execution = definitionByID[executionDefinitionID]?.updateExecutionCapability,
               asset.capability?.packageIdentifier == execution.packageIdentifier {
                executionCapabilities[asset.key] = execution
            }
        }

        for application in snapshot?.applications ?? [] {
            let definition = definitionForApplication(
                application,
                definitions: definitions
            )
            let owner: AIAssetOwner = .unknown
            let evidence = application.version.map {
                VersionEvidence(version: $0, source: .applicationBundle, confidence: .high)
            }
            append(AIUpdateAsset(
                key: AIUpdateAssetKey(
                    kind: .application,
                    owner: owner,
                    canonicalLocation: canonical(application.url)
                ),
                displayName: application.name,
                definitionID: definition?.id,
                localVersion: VersionEvidenceResolver.resolve(evidence.map { [$0] } ?? []),
                capability: nil
            ))
        }

        for cli in managementProjection.clis {
            guard let executableURL = cli.evidence.executableURL else { continue }
            let definitionID = toolDefinitionID(from: cli.owner)
            let definition = definitionID.flatMap { definitionByID[$0] }
            let evidence = cli.evidence.detectedVersion.map {
                VersionEvidence(version: $0, source: .cliProbe, confidence: .high)
            }
            append(AIUpdateAsset(
                key: AIUpdateAssetKey(
                    kind: .cli,
                    owner: owner(from: cli.owner),
                    canonicalLocation: canonical(executableURL)
                ),
                displayName: cli.displayName,
                definitionID: definitionID,
                localVersion: VersionEvidenceResolver.resolve(evidence.map { [$0] } ?? []),
                capability: definition?.updateCapability
            ), executionDefinitionID: definitionID)
        }

        for fact in packageFacts {
            let definition = definitionByID[fact.definitionID]
            let evidence = fact.version.map {
                VersionEvidence(version: $0, source: .packageReceipt, confidence: .high)
            }
            append(AIUpdateAsset(
                key: AIUpdateAssetKey(
                    kind: .package,
                    owner: .tool(definitionID: fact.definitionID),
                    canonicalLocation: canonical(fact.metadataURL)
                ),
                displayName: definition?.displayName ?? fact.packageName,
                definitionID: fact.definitionID,
                localVersion: VersionEvidenceResolver.resolve(evidence.map { [$0] } ?? []),
                capability: definition?.updateCapability
            ), executionDefinitionID: fact.definitionID)
        }

        for skill in (snapshot?.skills ?? []) + projectSkills {
            append(AIUpdateAsset(
                key: AIUpdateAssetKey(
                    kind: .skill,
                    owner: skill.owner,
                    canonicalLocation: canonical(skill.url)
                ),
                displayName: skill.name,
                definitionID: definitionID(from: skill.owner),
                localVersion: .unknown,
                capability: nil
            ))
        }

        for plugin in (snapshot?.plugins ?? []) + projectPlugins {
            let evidence = plugin.version.map {
                VersionEvidence(version: $0, source: .pluginManifest, confidence: .high)
            }
            append(AIUpdateAsset(
                key: AIUpdateAssetKey(
                    kind: .plugin,
                    owner: plugin.owner,
                    canonicalLocation: canonical(plugin.url)
                ),
                displayName: plugin.name,
                definitionID: definitionID(from: plugin.owner),
                localVersion: VersionEvidenceResolver.resolve(evidence.map { [$0] } ?? []),
                capability: nil
            ))
        }

        return AIUpdateAssetInventory(
            assets: assets.sorted { $0.key < $1.key },
            unsupportedResults: unsupported.sorted { $0.assetKey < $1.assetKey },
            executionCapabilities: executionCapabilities
        )
    }

    private static func definitionForApplication(
        _ application: ApplicationRecord,
        definitions: [AIToolDefinition]
    ) -> AIToolDefinition? {
        guard let bundleIdentifier = application.bundleIdentifier else { return nil }
        return definitions.first { $0.applicationBundleIdentifiers.contains(bundleIdentifier) }
    }

    private static func toolDefinitionID(from owner: AIToolOwner) -> String? {
        guard case .tool(let definitionID) = owner else { return nil }
        return definitionID
    }

    private static func owner(from owner: AIToolOwner) -> AIAssetOwner {
        switch owner {
        case .tool(let definitionID): .tool(definitionID: definitionID)
        case .shared: .shared
        }
    }

    private static func definitionID(from owner: AIAssetOwner) -> String? {
        guard case .tool(let definitionID) = owner else { return nil }
        return definitionID
    }

    private static func canonical(_ url: URL) -> String {
        url.canonicalizedDiscoveryPath
    }
}
