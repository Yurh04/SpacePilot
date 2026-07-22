import Foundation

enum L10n {
    static let allKeys: Set<String> = [
        "category.ai-data", "category.application", "category.cache", "category.conversation",
        "category.developer", "category.log", "category.model", "category.personal",
        "category.plugin", "category.skill", "category.system", "category.unclassified",
        "common.cancel", "common.location", "common.management", "common.risk", "common.scan",
        "common.skills", "common.space", "common.version", "nav.applications",
        "nav.cleanup-history", "nav.developer-ai", "nav.overview", "nav.storage",
        "plugins.discovery-failed", "plugins.empty", "plugins.official-handoff", "plugins.title",
        "risk.managed", "risk.rebuildable", "risk.safe", "risk.sensitive", "state.no-data",
        "state.preparing-summary"
    ]

    private static let resourceBundle: Bundle = {
        guard let appResources = Bundle.main.resourceURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: appResources,
                includingPropertiesForKeys: [.isDirectoryKey]
              ) else {
            return .module
        }
        let stagedCandidates = entries.filter {
            $0.pathExtension == "bundle" && $0.lastPathComponent.hasPrefix("SpacePilot_")
        }
        if stagedCandidates.count == 1,
           let stagedBundle = Bundle(url: stagedCandidates[0]) {
            return stagedBundle
        }
        return .module
    }()

    static var availableLocalizations: [String] {
        resourceBundle.localizations.map { identifier in
            canonicalLocalization(identifier)
        }
    }

    static func negotiatedLocalization(preferredLanguages: [String]? = nil) -> String {
        let supported = resourceBundle.localizations
        let preferences = preferredLanguages ?? Locale.preferredLanguages
        let selected = Bundle.preferredLocalizations(
            from: supported,
            forPreferences: preferences
        ).first ?? "en"
        return canonicalLocalization(selected)
    }

    private static func canonicalLocalization(_ identifier: String) -> String {
        identifier.caseInsensitiveCompare("zh-Hans") == .orderedSame ? "zh-Hans" : identifier
    }

    private static func value(
        _ key: String,
        default defaultValue: String,
        locale: Locale?
    ) -> String {
        let localization = locale.map {
            negotiatedLocalization(preferredLanguages: [$0.identifier])
        } ?? negotiatedLocalization()
        guard let path = resourceBundle.path(
            forResource: localization.lowercased(),
            ofType: "lproj"
        ),
              let bundle = Bundle(path: path) else {
            return defaultValue
        }
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func overview(locale: Locale? = nil) -> String {
        value("nav.overview", default: "Overview", locale: locale)
    }

    static func storage(locale: Locale? = nil) -> String {
        value("nav.storage", default: "Storage", locale: locale)
    }

    static func applications(locale: Locale? = nil) -> String {
        value("nav.applications", default: "Applications", locale: locale)
    }

    static func developerAI(locale: Locale? = nil) -> String {
        value("nav.developer-ai", default: "Developer & AI", locale: locale)
    }

    static func cleanupHistory(locale: Locale? = nil) -> String {
        value("nav.cleanup-history", default: "Cleanup History", locale: locale)
    }

    static func scan(locale: Locale? = nil) -> String {
        value("common.scan", default: "Scan", locale: locale)
    }

    static func cancel(locale: Locale? = nil) -> String {
        value("common.cancel", default: "Cancel", locale: locale)
    }

    static func space(locale: Locale? = nil) -> String {
        value("common.space", default: "Space", locale: locale)
    }

    static func version(locale: Locale? = nil) -> String {
        value("common.version", default: "Version", locale: locale)
    }

    static func location(locale: Locale? = nil) -> String {
        value("common.location", default: "Location", locale: locale)
    }

    static func risk(locale: Locale? = nil) -> String {
        value("common.risk", default: "Risk", locale: locale)
    }

    static func skills(locale: Locale? = nil) -> String {
        value("common.skills", default: "Skills", locale: locale)
    }

    static func management(locale: Locale? = nil) -> String {
        value("common.management", default: "Management", locale: locale)
    }

    static func preparingSummary(locale: Locale? = nil) -> String {
        value("state.preparing-summary", default: "Preparing summary…", locale: locale)
    }

    static func noData(locale: Locale? = nil) -> String {
        value("state.no-data", default: "Run a scan to see local results.", locale: locale)
    }

    static func plugins(locale: Locale? = nil) -> String {
        value("plugins.title", default: "Plugins", locale: locale)
    }

    static func noPluginsInstalled(locale: Locale? = nil) -> String {
        value("plugins.empty", default: "No Plugins installed", locale: locale)
    }

    static func pluginDiscoveryFailed(locale: Locale? = nil) -> String {
        value("plugins.discovery-failed", default: "Plugin discovery failed", locale: locale)
    }

    static func officialHandoff(locale: Locale? = nil) -> String {
        value("plugins.official-handoff", default: "Official handoff", locale: locale)
    }

    static func riskSafe(locale: Locale? = nil) -> String {
        value("risk.safe", default: "Safe to clean", locale: locale)
    }

    static func riskRebuildable(locale: Locale? = nil) -> String {
        value("risk.rebuildable", default: "Rebuildable", locale: locale)
    }

    static func riskSensitive(locale: Locale? = nil) -> String {
        value("risk.sensitive", default: "Sensitive", locale: locale)
    }

    static func riskManaged(locale: Locale? = nil) -> String {
        value("risk.managed", default: "Provider managed", locale: locale)
    }

    static func categoryApplication(locale: Locale? = nil) -> String {
        value("category.application", default: "Application Data", locale: locale)
    }

    static func categoryPersonal(locale: Locale? = nil) -> String {
        value("category.personal", default: "Personal Files", locale: locale)
    }

    static func categoryDeveloper(locale: Locale? = nil) -> String {
        value("category.developer", default: "Developer Files", locale: locale)
    }

    static func categoryAIData(locale: Locale? = nil) -> String {
        value("category.ai-data", default: "AI Data", locale: locale)
    }

    static func categoryCache(locale: Locale? = nil) -> String {
        value("category.cache", default: "Caches", locale: locale)
    }

    static func categoryLog(locale: Locale? = nil) -> String {
        value("category.log", default: "Logs", locale: locale)
    }

    static func categoryConversation(locale: Locale? = nil) -> String {
        value("category.conversation", default: "Conversations", locale: locale)
    }

    static func categoryModel(locale: Locale? = nil) -> String {
        value("category.model", default: "Models", locale: locale)
    }

    static func categoryPlugin(locale: Locale? = nil) -> String {
        value("category.plugin", default: "Plugins", locale: locale)
    }

    static func categorySkill(locale: Locale? = nil) -> String {
        value("category.skill", default: "Skills", locale: locale)
    }

    static func categorySystem(locale: Locale? = nil) -> String {
        value("category.system", default: "System", locale: locale)
    }

    static func categoryUnclassified(locale: Locale? = nil) -> String {
        value("category.unclassified", default: "Unclassified", locale: locale)
    }
}
