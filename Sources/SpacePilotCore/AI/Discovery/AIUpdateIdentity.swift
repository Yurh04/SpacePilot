import Foundation

public enum AIUpdateIdentity {
    public static func cli(_ record: AIToolRecord) -> AIUpdateAssetKey {
        let owner: AIAssetOwner
        switch record.owner {
        case .tool(let id): owner = .tool(definitionID: id)
        case .shared: owner = .shared
        }
        return AIUpdateAssetKey(kind: .cli, owner: owner,
            canonicalLocation: record.evidence.executableURL?.canonicalizedDiscoveryPath
                ?? "unresolved-cli:\(record.id)")
    }

    public static func other(_ tool: OtherAIToolRecord, assets: [AIUpdateAsset]) -> AIUpdateAssetKey {
        if let key = tool.cliUpdateKey { return key }
        // A registration/config path is not an executable or an app bundle.
        if tool.installMethod == .applicationBundle, tool.url.pathExtension == "app",
           let app = assets.first(where: {
               $0.key.kind == .application && $0.key.canonicalLocation == tool.url.canonicalizedDiscoveryPath
           }) { return app.key }
        return AIUpdateAssetKey(kind: .package, owner: .unknown, canonicalLocation: tool.id)
    }
}
