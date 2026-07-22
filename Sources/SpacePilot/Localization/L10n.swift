import Foundation

enum L10n {
    private static let resourceBundle: Bundle = {
        let stagedBundleURL = Bundle.main.resourceURL?
            .appending(path: "SpacePilot_SpacePilot.bundle", directoryHint: .isDirectory)
        if let stagedBundleURL, let stagedBundle = Bundle(url: stagedBundleURL) {
            return stagedBundle
        }
        return .module
    }()

    static var availableLocalizations: [String] {
        resourceBundle.localizations.map { identifier in
            identifier.caseInsensitiveCompare("zh-Hans") == .orderedSame ? "zh-Hans" : identifier
        }
    }

    private static func value(
        _ key: String,
        default defaultValue: String,
        locale: Locale
    ) -> String {
        let localization = locale.language.languageCode?.identifier == "zh"
            && locale.language.script?.identifier != "Hant"
            ? "zh-hans"
            : "en"
        guard let path = resourceBundle.path(forResource: localization, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return defaultValue
        }
        return bundle.localizedString(forKey: key, value: defaultValue, table: nil)
    }

    static func overview(locale: Locale = .current) -> String {
        value("nav.overview", default: "Overview", locale: locale)
    }

    static func storage(locale: Locale = .current) -> String {
        value("nav.storage", default: "Storage", locale: locale)
    }

    static func applications(locale: Locale = .current) -> String {
        value("nav.applications", default: "Applications", locale: locale)
    }

    static func developerAI(locale: Locale = .current) -> String {
        value("nav.developer-ai", default: "Developer & AI", locale: locale)
    }

    static func cleanupHistory(locale: Locale = .current) -> String {
        value("nav.cleanup-history", default: "Cleanup History", locale: locale)
    }

    static func scan(locale: Locale = .current) -> String {
        value("common.scan", default: "Scan", locale: locale)
    }

    static func cancel(locale: Locale = .current) -> String {
        value("common.cancel", default: "Cancel", locale: locale)
    }

    static func space(locale: Locale = .current) -> String {
        value("common.space", default: "Space", locale: locale)
    }

    static func version(locale: Locale = .current) -> String {
        value("common.version", default: "Version", locale: locale)
    }

    static func location(locale: Locale = .current) -> String {
        value("common.location", default: "Location", locale: locale)
    }

    static func risk(locale: Locale = .current) -> String {
        value("common.risk", default: "Risk", locale: locale)
    }

    static func skills(locale: Locale = .current) -> String {
        value("common.skills", default: "Skills", locale: locale)
    }

    static func management(locale: Locale = .current) -> String {
        value("common.management", default: "Management", locale: locale)
    }

    static func preparingSummary(locale: Locale = .current) -> String {
        value("state.preparing-summary", default: "Preparing summary…", locale: locale)
    }

    static func noData(locale: Locale = .current) -> String {
        value("state.no-data", default: "Run a scan to see local results.", locale: locale)
    }

    static func plugins(locale: Locale = .current) -> String {
        value("plugins.title", default: "Plugins", locale: locale)
    }

    static func noPluginsInstalled(locale: Locale = .current) -> String {
        value("plugins.empty", default: "No Plugins installed", locale: locale)
    }

    static func pluginDiscoveryFailed(locale: Locale = .current) -> String {
        value("plugins.discovery-failed", default: "Plugin discovery failed", locale: locale)
    }

    static func officialHandoff(locale: Locale = .current) -> String {
        value("plugins.official-handoff", default: "Official handoff", locale: locale)
    }

    static func riskSafe(locale: Locale = .current) -> String {
        value("risk.safe", default: "Safe to clean", locale: locale)
    }

    static func riskRebuildable(locale: Locale = .current) -> String {
        value("risk.rebuildable", default: "Rebuildable", locale: locale)
    }

    static func riskSensitive(locale: Locale = .current) -> String {
        value("risk.sensitive", default: "Sensitive", locale: locale)
    }

    static func riskManaged(locale: Locale = .current) -> String {
        value("risk.managed", default: "Provider managed", locale: locale)
    }

    static func categoryApplication(locale: Locale = .current) -> String {
        value("category.application", default: "Application Data", locale: locale)
    }

    static func categoryPersonal(locale: Locale = .current) -> String {
        value("category.personal", default: "Personal Files", locale: locale)
    }

    static func categoryDeveloper(locale: Locale = .current) -> String {
        value("category.developer", default: "Developer Files", locale: locale)
    }

    static func categoryAIData(locale: Locale = .current) -> String {
        value("category.ai-data", default: "AI Data", locale: locale)
    }

    static func categoryCache(locale: Locale = .current) -> String {
        value("category.cache", default: "Caches", locale: locale)
    }

    static func categoryLog(locale: Locale = .current) -> String {
        value("category.log", default: "Logs", locale: locale)
    }

    static func categoryConversation(locale: Locale = .current) -> String {
        value("category.conversation", default: "Conversations", locale: locale)
    }

    static func categoryModel(locale: Locale = .current) -> String {
        value("category.model", default: "Models", locale: locale)
    }

    static func categoryPlugin(locale: Locale = .current) -> String {
        value("category.plugin", default: "Plugins", locale: locale)
    }

    static func categorySkill(locale: Locale = .current) -> String {
        value("category.skill", default: "Skills", locale: locale)
    }

    static func categorySystem(locale: Locale = .current) -> String {
        value("category.system", default: "System", locale: locale)
    }

    static func categoryUnclassified(locale: Locale = .current) -> String {
        value("category.unclassified", default: "Unclassified", locale: locale)
    }
}
