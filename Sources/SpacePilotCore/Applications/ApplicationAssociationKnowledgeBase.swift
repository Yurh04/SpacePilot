import Foundation

/// A versioned, read-only catalogue of paths that may be associated with an
/// application. Knowledge-base results are inspection candidates only; cleanup
/// policy remains the responsibility of the uninstall planner.
public struct ApplicationAssociationKnowledgeBase: Codable, Hashable, Sendable {
    public static let supportedSchemaVersion = 1

    public let schemaVersion: Int
    public let contentVersion: String
    public let rules: [ApplicationAssociationKnowledgeRule]

    public init(
        schemaVersion: Int,
        contentVersion: String,
        rules: [ApplicationAssociationKnowledgeRule]
    ) {
        self.schemaVersion = schemaVersion
        self.contentVersion = contentVersion
        self.rules = rules
    }

    public static func decode(_ data: Data) throws -> Self {
        let knowledgeBase: Self
        do {
            knowledgeBase = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ApplicationAssociationKnowledgeError.invalidDocument(
                String(describing: error)
            )
        }
        try knowledgeBase.validate()
        return knowledgeBase
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func validate() throws {
        guard schemaVersion == Self.supportedSchemaVersion else {
            throw ApplicationAssociationKnowledgeError.unsupportedSchemaVersion(
                schemaVersion
            )
        }
        guard !contentVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApplicationAssociationKnowledgeError.emptyContentVersion
        }

        var identifiers = Set<String>()
        for rule in rules {
            guard identifiers.insert(rule.id).inserted else {
                throw ApplicationAssociationKnowledgeError.duplicateRuleID(rule.id)
            }
            try rule.validate()
        }
    }

    public func candidates(
        for context: ApplicationAssociationKnowledgeContext,
        homeDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [ApplicationAssociationKnowledgeCandidate] {
        try validate()
        try context.validate()

        return try rules
            .filter {
                try $0.match.matches(
                    context,
                    fileManager: fileManager
                )
            }
            .flatMap { rule in
                try rule.paths.map { pathRule in
                    let url = try Self.resolve(
                        pathRule.template,
                        scope: pathRule.scope,
                        context: context,
                        homeDirectory: homeDirectory
                    )
                    let excludedURLs = try pathRule.excludedPaths.map {
                        try Self.resolve(
                            $0,
                            scope: pathRule.scope,
                            context: context,
                            homeDirectory: homeDirectory
                        )
                    }

                    return ApplicationAssociationKnowledgeCandidate(
                        ruleID: rule.id,
                        url: url,
                        excludedURLs: excludedURLs,
                        category: pathRule.category,
                        risk: pathRule.risk,
                        evidence: pathRule.evidence,
                        confidence: pathRule.confidence,
                        ownership: pathRule.ownership,
                        disposition: pathRule.disposition
                    )
                }
            }
    }

    private static func resolve(
        _ template: String,
        scope: ApplicationAssociationPathScope,
        context: ApplicationAssociationKnowledgeContext,
        homeDirectory: URL
    ) throws -> URL {
        let renderedPath = try render(template, context: context)
        try validateRelativePath(renderedPath, field: template)

        let root: URL
        switch scope {
        case .homeDirectory:
            root = homeDirectory
        case .applicationBundle:
            root = context.applicationBundleURL
        }

        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        var canonicalTarget = canonicalRoot
        for component in renderedPath.split(separator: "/") {
            canonicalTarget = canonicalTarget
                .appending(path: String(component))
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard isStrictlyWithin(canonicalTarget, root: canonicalRoot) else {
                throw ApplicationAssociationKnowledgeError.pathEscapesScope(template)
            }
        }
        return canonicalTarget
    }

    fileprivate static func validateTemplate(_ template: String) throws {
        var scrubbed = template
        for placeholder in ApplicationAssociationPathPlaceholder.allCases {
            scrubbed = scrubbed.replacingOccurrences(
                of: placeholder.rawValue,
                with: "placeholder"
            )
        }
        guard !scrubbed.contains("{"), !scrubbed.contains("}") else {
            throw ApplicationAssociationKnowledgeError.unknownPlaceholder(template)
        }
        try validateRelativePath(scrubbed, field: template)
    }

    fileprivate static func validateRelativePath(
        _ path: String,
        field: String
    ) throws {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\0"),
              !path.contains("\\")
        else {
            throw ApplicationAssociationKnowledgeError.unsafeRelativePath(field)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".."
        }) else {
            throw ApplicationAssociationKnowledgeError.unsafeRelativePath(field)
        }
    }

    private static func render(
        _ template: String,
        context: ApplicationAssociationKnowledgeContext
    ) throws -> String {
        var result = template
        let values: [(ApplicationAssociationPathPlaceholder, String?)] = [
            (.bundleIdentifier, context.bundleIdentifier),
            (.teamIdentifier, context.teamIdentifier),
            (.applicationName, context.applicationName)
        ]

        for (placeholder, value) in values
        where result.contains(placeholder.rawValue) {
            guard let value else {
                throw ApplicationAssociationKnowledgeError.missingPlaceholderValue(
                    placeholder.rawValue
                )
            }
            try validatePathComponent(value, field: placeholder.rawValue)
            result = result.replacingOccurrences(
                of: placeholder.rawValue,
                with: value
            )
        }
        return result
    }

    private static func validatePathComponent(
        _ component: String,
        field: String
    ) throws {
        guard !component.isEmpty,
              component != ".",
              component != "..",
              !component.contains("/"),
              !component.contains("\\"),
              !component.contains("\0")
        else {
            throw ApplicationAssociationKnowledgeError.unsafePlaceholderValue(field)
        }
    }

    fileprivate static func isStrictlyWithin(_ url: URL, root: URL) -> Bool {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return url.path.hasPrefix(rootPath)
    }
}

public struct ApplicationAssociationKnowledgeRule: Codable, Hashable, Sendable {
    public let id: String
    public let match: ApplicationAssociationKnowledgeMatch
    public let paths: [ApplicationAssociationPathRule]

    public init(
        id: String,
        match: ApplicationAssociationKnowledgeMatch,
        paths: [ApplicationAssociationPathRule]
    ) {
        self.id = id
        self.match = match
        self.paths = paths
    }

    fileprivate func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ApplicationAssociationKnowledgeError.emptyRuleID
        }
        guard !paths.isEmpty else {
            throw ApplicationAssociationKnowledgeError.ruleHasNoPaths(id)
        }
        try match.validate(ruleID: id)
        for path in paths {
            try path.validate()
        }
    }
}

public struct ApplicationAssociationKnowledgeMatch: Codable, Hashable, Sendable {
    public let bundleIdentifiers: Set<String>
    public let teamIdentifiers: Set<String>
    public let requiredBundlePaths: Set<String>

    public init(
        bundleIdentifiers: Set<String> = [],
        teamIdentifiers: Set<String> = [],
        requiredBundlePaths: Set<String> = []
    ) {
        self.bundleIdentifiers = bundleIdentifiers
        self.teamIdentifiers = teamIdentifiers
        self.requiredBundlePaths = requiredBundlePaths
    }

    fileprivate func validate(ruleID: String) throws {
        guard !bundleIdentifiers.isEmpty
                || !teamIdentifiers.isEmpty
                || !requiredBundlePaths.isEmpty
        else {
            throw ApplicationAssociationKnowledgeError.ruleHasNoMatcher(ruleID)
        }
        for identifier in bundleIdentifiers {
            try Self.validateIdentifier(identifier)
        }
        for identifier in teamIdentifiers {
            try Self.validateIdentifier(identifier)
        }
        for path in requiredBundlePaths {
            try ApplicationAssociationKnowledgeBase.validateRelativePath(
                path,
                field: path
            )
        }
    }

    fileprivate func matches(
        _ context: ApplicationAssociationKnowledgeContext,
        fileManager: FileManager
    ) throws -> Bool {
        if !bundleIdentifiers.isEmpty,
           !bundleIdentifiers.contains(context.bundleIdentifier ?? "") {
            return false
        }
        if !teamIdentifiers.isEmpty,
           !teamIdentifiers.contains(context.teamIdentifier ?? "") {
            return false
        }

        let canonicalBundle = context.applicationBundleURL
            .standardizedFileURL
            .resolvingSymlinksInPath()
        for relativePath in requiredBundlePaths {
            let marker = canonicalBundle
                .appending(path: relativePath)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard ApplicationAssociationKnowledgeBase.isStrictlyWithin(
                marker,
                root: canonicalBundle
            ), fileManager.fileExists(atPath: marker.path) else {
                return false
            }
        }
        return true
    }

    private static func validateIdentifier(_ identifier: String) throws {
        guard !identifier.isEmpty,
              !identifier.contains("/"),
              !identifier.contains("\\"),
              !identifier.contains("\0")
        else {
            throw ApplicationAssociationKnowledgeError.invalidIdentifier(identifier)
        }
    }
}

public struct ApplicationAssociationPathRule: Codable, Hashable, Sendable {
    public let scope: ApplicationAssociationPathScope
    public let template: String
    public let excludedPaths: [String]
    public let category: ItemCategory
    public let risk: RiskLevel
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let ownership: AssociationOwnership
    public let disposition: ApplicationAssociationCandidateDisposition

    public init(
        scope: ApplicationAssociationPathScope,
        template: String,
        excludedPaths: [String] = [],
        category: ItemCategory,
        risk: RiskLevel,
        evidence: AssociationEvidence = .knownRule,
        confidence: AssociationConfidence,
        ownership: AssociationOwnership,
        disposition: ApplicationAssociationCandidateDisposition = .inspectOnly
    ) {
        self.scope = scope
        self.template = template
        self.excludedPaths = excludedPaths
        self.category = category
        self.risk = risk
        self.evidence = evidence
        self.confidence = confidence
        self.ownership = ownership
        self.disposition = disposition
    }

    fileprivate func validate() throws {
        try ApplicationAssociationKnowledgeBase.validateTemplate(template)
        for exclusion in excludedPaths {
            try ApplicationAssociationKnowledgeBase.validateTemplate(exclusion)
        }
        guard disposition == .inspectOnly else {
            throw ApplicationAssociationKnowledgeError.unsafeDisposition
        }
    }
}

public enum ApplicationAssociationPathScope: String, Codable, Hashable, Sendable {
    case homeDirectory
    case applicationBundle
}

public enum ApplicationAssociationCandidateDisposition: String, Codable, Hashable, Sendable {
    /// The candidate may be scanned and explained, but never directly removed.
    case inspectOnly
}

private enum ApplicationAssociationPathPlaceholder: String, CaseIterable {
    case bundleIdentifier = "{bundleID}"
    case teamIdentifier = "{teamID}"
    case applicationName = "{appName}"
}

public struct ApplicationAssociationKnowledgeContext: Hashable, Sendable {
    public let applicationName: String
    public let bundleIdentifier: String?
    public let teamIdentifier: String?
    public let applicationBundleURL: URL

    public init(
        applicationName: String,
        bundleIdentifier: String?,
        teamIdentifier: String?,
        applicationBundleURL: URL
    ) {
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.teamIdentifier = teamIdentifier
        self.applicationBundleURL = applicationBundleURL
    }

    fileprivate func validate() throws {
        guard applicationBundleURL.pathExtension.lowercased() == "app",
              applicationBundleURL.isFileURL
        else {
            throw ApplicationAssociationKnowledgeError.invalidApplicationBundle
        }
    }
}

public struct ApplicationAssociationKnowledgeCandidate: Hashable, Sendable {
    public let ruleID: String
    public let url: URL
    public let excludedURLs: [URL]
    public let category: ItemCategory
    public let risk: RiskLevel
    public let evidence: AssociationEvidence
    public let confidence: AssociationConfidence
    public let ownership: AssociationOwnership
    public let disposition: ApplicationAssociationCandidateDisposition
}

public enum ApplicationAssociationKnowledgeError: Error, Equatable, Sendable {
    case invalidDocument(String)
    case unsupportedSchemaVersion(Int)
    case emptyContentVersion
    case emptyRuleID
    case duplicateRuleID(String)
    case ruleHasNoMatcher(String)
    case ruleHasNoPaths(String)
    case invalidIdentifier(String)
    case unsafeRelativePath(String)
    case unknownPlaceholder(String)
    case missingPlaceholderValue(String)
    case unsafePlaceholderValue(String)
    case pathEscapesScope(String)
    case invalidApplicationBundle
    case unsafeDisposition
}

public extension ApplicationAssociationKnowledgeBase {
    /// Built-in version 1 examples. All results are deliberately inspect-only.
    static let builtInV1 = ApplicationAssociationKnowledgeBase(
        schemaVersion: 1,
        contentVersion: "1.2.0",
        rules: [
            ApplicationAssociationKnowledgeRule(
                id: "product.openai.chatgpt-codex.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.openai.codex"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/Codex",
                        category: .application,
                        risk: .sensitive,
                        confidence: .high,
                        ownership: .owned
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/OpenAI/Codex",
                        category: .application,
                        risk: .sensitive,
                        confidence: .high,
                        ownership: .owned
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "framework.electron.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    requiredBundlePaths: [
                        "Contents/Frameworks/Electron Framework.framework"
                    ]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/{appName}",
                        excludedPaths: [
                            "Library/Application Support/{appName}/User Data/Default/Login Data"
                        ],
                        category: .application,
                        risk: .sensitive,
                        confidence: .medium,
                        ownership: .possible
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Caches/{bundleID}",
                        category: .cache,
                        risk: .rebuildable,
                        confidence: .medium,
                        ownership: .owned
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Preferences/{bundleID}.plist",
                        category: .application,
                        risk: .sensitive,
                        confidence: .medium,
                        ownership: .owned
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "framework.sparkle.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    requiredBundlePaths: [
                        "Contents/Frameworks/Sparkle.framework"
                    ]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Caches/{bundleID}/org.sparkle-project.Sparkle",
                        category: .cache,
                        risk: .rebuildable,
                        confidence: .high,
                        ownership: .owned
                    ),
                    ApplicationAssociationPathRule(
                        scope: .applicationBundle,
                        template: "Contents/Frameworks/Sparkle.framework",
                        category: .application,
                        risk: .managed,
                        confidence: .high,
                        ownership: .owned
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "integration.chrome-native-messaging.openai-codex.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.openai.codex"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/Google/Chrome/NativeMessagingHosts/com.openai.codexextension.json",
                        category: .plugin,
                        risk: .rebuildable,
                        confidence: .high,
                        ownership: .owned
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "installer.homebrew-cask.docker.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.docker.docker"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Caches/Homebrew/Cask/docker",
                        category: .cache,
                        risk: .sensitive,
                        confidence: .low,
                        ownership: .shared
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "product.vscode.user-data.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.microsoft.VSCode"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: ".vscode",
                        category: .developer,
                        risk: .sensitive,
                        confidence: .high,
                        ownership: .owned
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: ".vscode-shared",
                        category: .developer,
                        risk: .sensitive,
                        confidence: .medium,
                        ownership: .possible
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "product.cursor.user-data.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.todesktop.230313mzl4w4u92"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: ".cursor",
                        category: .aiData,
                        risk: .sensitive,
                        confidence: .high,
                        ownership: .owned
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "product.docker.cli-data.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.docker.docker"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: ".docker",
                        category: .developer,
                        risk: .sensitive,
                        confidence: .medium,
                        ownership: .shared
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "service.microsoft.edge-updater.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: ["com.microsoft.edgemac"]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/Microsoft/EdgeUpdater",
                        category: .application,
                        risk: .rebuildable,
                        confidence: .medium,
                        ownership: .shared
                    )
                ]
            ),
            ApplicationAssociationKnowledgeRule(
                id: "vendor.jetbrains.shared-data.v1",
                match: ApplicationAssociationKnowledgeMatch(
                    bundleIdentifiers: [
                        "com.jetbrains.intellij.ce",
                        "com.jetbrains.pycharm.ce"
                    ]
                ),
                paths: [
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Application Support/JetBrains",
                        category: .developer,
                        risk: .sensitive,
                        confidence: .medium,
                        ownership: .shared
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Caches/JetBrains",
                        category: .cache,
                        risk: .rebuildable,
                        confidence: .medium,
                        ownership: .shared
                    ),
                    ApplicationAssociationPathRule(
                        scope: .homeDirectory,
                        template: "Library/Logs/JetBrains",
                        category: .log,
                        risk: .rebuildable,
                        confidence: .medium,
                        ownership: .shared
                    )
                ]
            )
        ]
    )
}
