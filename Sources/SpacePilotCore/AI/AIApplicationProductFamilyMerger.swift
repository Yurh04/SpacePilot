import Foundation

public struct AIApplicationProductFamilyMerger: Sendable {
    public init() {}

    public func mergeChatGPTAndCodex(
        in applications: [AIApplicationRecord]
    ) -> [AIApplicationRecord] {
        guard let codexIndex = applications.firstIndex(where: {
            $0.name.caseInsensitiveCompare("Codex") == .orderedSame
                && $0.supportLevel == .deep
        }), let chatGPTIndex = applications.firstIndex(where: {
            $0.name.caseInsensitiveCompare("ChatGPT") == .orderedSame
        }), codexIndex != chatGPTIndex else {
            return applications
        }

        let codex = applications[codexIndex]
        let chatGPT = applications[chatGPTIndex]
        let merged = AIApplicationRecord(
            id: codex.id,
            name: "ChatGPT + Codex",
            bundleIdentifier: codex.bundleIdentifier
                ?? chatGPT.bundleIdentifier,
            applicationURL: chatGPT.applicationURL
                ?? codex.applicationURL,
            rootURLs: uniqueURLs(
                codex.rootURLs + chatGPT.rootURLs
            ),
            itemIDs: codex.itemIDs.union(chatGPT.itemIDs),
            pluginIDs: codex.pluginIDs.union(chatGPT.pluginIDs),
            skillIDs: codex.skillIDs.union(chatGPT.skillIDs),
            applicationAllocatedSize: max(
                codex.applicationAllocatedSize,
                chatGPT.applicationAllocatedSize
            ),
            supportLevel: .deep
        )

        return applications.enumerated().compactMap { index, application in
            if index == codexIndex { return merged }
            if index == chatGPTIndex { return nil }
            return application
        }
    }

    private func uniqueURLs(_ urls: [URL]) -> [URL] {
        var paths = Set<String>()
        return urls.compactMap { url in
            let standardized = url.standardizedFileURL
            return paths.insert(standardized.path).inserted
                ? standardized
                : nil
        }
    }
}
