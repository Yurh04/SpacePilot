import Foundation
import SpacePilotCore

enum L10n {
    struct Copy: Sendable {
        fileprivate let key: String
        fileprivate let english: String

        static let aiBasicFootprint = Self(key: "ai.basic-footprint", english: "Basic footprint")
        static let aiDataItems = Self(key: "ai.data-items", english: "Data items")
        static let aiDeepAnalysis = Self(key: "ai.deep-analysis", english: "Deep analysis")
        static let aiDeveloperStorage = Self(key: "ai.developer-storage", english: "Developer storage")
        static let aiLocalFootprint = Self(key: "ai.local-footprint", english: "Local footprint")
        static let aiNoContentIndexed = Self(key: "ai.no-content-indexed", english: "Conversation and log contents are not indexed.")
        static let aiPluginsManaged = Self(key: "ai.plugins-managed", english: "Plugin packages are managed by their owning application.")
        static let aiPrivacy = Self(key: "ai.privacy", english: "Privacy")
        static let aiSearching = Self(key: "ai.searching", english: "Searching…")
        static let aiSection = Self(key: "ai.section", english: "Section")
        static let aiSelectApplication = Self(key: "ai.select-application", english: "Select an AI application")
        static let aiStorageBreakdown = Self(key: "ai.storage-breakdown", english: "Space breakdown")
        static let aiTotalIndexedSpace = Self(key: "ai.total-indexed-space", english: "Total indexed space")
        static let application = Self(key: "app.application", english: "Application")
        static let applicationOnlyHighConfidence = Self(key: "app.only-high-confidence", english: "Only high-confidence related files are preselected.")
        static let applicationRelated = Self(key: "app.related", english: "Related")
        static let applicationReset = Self(key: "app.reset", english: "Reset…")
        static let applicationReviewReset = Self(key: "app.review-reset", english: "Review Reset…")
        static let applicationReviewUninstall = Self(key: "app.review-uninstall", english: "Review Uninstall…")
        static let applicationSearch = Self(key: "app.search-applications", english: "Search applications")
        static let applicationTotalSpace = Self(key: "app.total-space", english: "Total space")
        static let applicationUninstall = Self(key: "app.uninstall", english: "Uninstall…")
        static let cleanupConfirmSensitive = Self(key: "cleanup.confirm-sensitive", english: "Also move the sensitive conversation, project, or settings data listed above")
        static let cleanupConfirmTrash = Self(key: "cleanup.confirm-trash", english: "I understand these items will be moved to the Trash")
        static let cleanupClearSelection = Self(key: "cleanup.clear-selection", english: "Clear")
        static let cleanupHistoryEmpty = Self(key: "cleanup.history-empty", english: "No cleanup history")
        static let cleanupHistoryEmptyDescription = Self(key: "cleanup.history-empty-description", english: "Verified cleanup operations will appear here.")
        static let cleanupMoveSelectedTrash = Self(key: "cleanup.move-selected-trash", english: "Move Selected to Trash")
        static let cleanupMoveTrash = Self(key: "cleanup.move-trash", english: "Move to Trash")
        static let cleanupMoving = Self(key: "cleanup.moving", english: "Moving…")
        static let cleanupReview = Self(key: "cleanup.review", english: "Review Cleanup")
        static let cleanupReviewDescription = Self(key: "cleanup.review-description", english: "These exact items will be moved to the Trash. You can restore them from the Trash until it is emptied.")
        static let cleanupSelectAll = Self(key: "cleanup.select-all", english: "Select All")
        static let category = Self(key: "common.category", english: "Category")
        static let items = Self(key: "common.items", english: "Items")
        static let name = Self(key: "common.name", english: "Name")
        static let plugin = Self(key: "common.plugin", english: "Plugin")
        static let revealFinder = Self(key: "common.reveal-finder", english: "Reveal in Finder")
        static let searchCurrent = Self(key: "common.search-current", english: "Search current view")
        static let skill = Self(key: "common.skill", english: "Skill")
        static let source = Self(key: "common.source", english: "Source")
        static let overviewAnalyzeMac = Self(key: "overview.analyze-mac", english: "Analyze this Mac")
        static let overviewAnalyzedCategoriesChart = Self(key: "overview.analyzed-categories-chart", english: "Locally analyzed categories")
        static let overviewAnalyzedCategoriesDescription = Self(key: "overview.analyzed-categories-description", english: "These bars cover locally analyzed data, not the whole disk.")
        static let overviewAnalyzedCategoriesEmpty = Self(key: "overview.analyzed-categories-empty", english: "No locally analyzed categories are available yet.")
        static let overviewAnalyzedLocally = Self(key: "overview.analyzed-locally", english: "Analyzed locally")
        static let overviewDiskAvailable = Self(key: "overview.disk-available", english: "Available")
        static let overviewDiskCapacityChart = Self(key: "overview.disk-capacity-chart", english: "Internal disk capacity")
        static let overviewDiskCapacityUnavailableDescription = Self(key: "overview.disk-capacity-unavailable-description", english: "Whole-disk capacity is unavailable. Only locally analyzed data is shown.")
        static let overviewDiskTotal = Self(key: "overview.disk-total", english: "Total capacity")
        static let overviewDiskUsed = Self(key: "overview.disk-used", english: "Used")
        static let overviewInternalDiskUsed = Self(key: "overview.internal-disk-used", english: "Internal disk used")
        static let overviewLimitedCoverage = Self(key: "overview.limited-coverage", english: "Limited coverage")
        static let overviewLimitedCoverageDescription = Self(key: "overview.limited-coverage-description", english: "Some folders could not be read. Results show only verified data.")
        static let overviewNoRecommendations = Self(key: "overview.no-recommendations", english: "No safe cleanup recommendations yet.")
        static let overviewSafeRecommendations = Self(key: "overview.safe-recommendations", english: "Safe recommendations")
        static let overviewStartScan = Self(key: "overview.start-scan", english: "Start Scan")
        static let overviewStorageGlance = Self(key: "overview.storage-glance", english: "Storage at a glance")
        static let overviewWorksLocally = Self(key: "overview.works-locally", english: "SpacePilot works locally and indexes metadata only.")
        static let pluginDiagnosticEmptySkill = Self(key: "plugins.diagnostic-empty-skill", english: "A Plugin skill declaration was rejected or empty.")
        static let pluginDiagnosticGeneric = Self(key: "plugins.diagnostic-generic", english: "Plugin discovery reported an issue.")
        static let pluginDiagnosticInvalidManifest = Self(key: "plugins.diagnostic-invalid-manifest", english: "A Plugin manifest could not be read.")
        static let pluginDiagnosticMissingManifest = Self(key: "plugins.diagnostic-missing-manifest", english: "A Plugin manifest could not be found.")
        static let pluginDiagnosticPathInaccessible = Self(key: "plugins.diagnostic-path-inaccessible", english: "A Plugin path could not be accessed.")
        static let scanCancelled = Self(key: "scan.cancelled", english: "Scan cancelled")
        static let settingsDiagnostics = Self(key: "settings.diagnostics", english: "Diagnostics")
        static let settingsDiagnosticsDescription = Self(key: "settings.diagnostics-description", english: "Exported diagnostics contain counts and status metadata, not file paths, conversations, or log contents.")
        static let settingsDiskAccess = Self(key: "settings.disk-access", english: "Disk access")
        static let settingsDiskAccessDescription = Self(key: "settings.disk-access-description", english: "Grant Full Disk Access only if you want broader coverage. SpacePilot reports inaccessible folders instead of guessing.")
        static let settingsExportDiagnostics = Self(key: "settings.export-diagnostics", english: "Export Diagnostics…")
        static let settingsOpenDiskAccess = Self(key: "settings.open-disk-access", english: "Open Full Disk Access Settings")
        static let settingsPrivacy = Self(key: "settings.privacy", english: "Privacy")
        static let settingsPrivacyDescription = Self(key: "settings.privacy-description", english: "All analysis stays on this Mac. SpacePilot stores metadata, not conversation or log contents.")
        static let storageAllAnalyzed = Self(key: "storage.all-analyzed", english: "All Analyzed Items")
        static let storageAvailable = Self(key: "storage.available", english: "Available")
        static let storageCategories = Self(key: "storage.categories", english: "Categories")
        static let storageInternalDisk = Self(key: "storage.internal-disk", english: "Internal Disk")
        static let storageLargest = Self(key: "storage.largest", english: "Largest")
        static let storageLargestItems = Self(key: "storage.largest-items", english: "Largest analyzed items")
        static let storageNoMatching = Self(key: "storage.no-matching", english: "No Matching Items")
        static let storageNoMatchingDescription = Self(key: "storage.no-matching-description", english: "Choose another category or display mode.")
        static let storageOldItems = Self(key: "storage.old-items", english: "Not modified in 180+ days")
        static let storageOlder180 = Self(key: "storage.older-180", english: "Older than 180 days")
        static let storageReviewSafeCleanup = Self(key: "storage.review-safe-cleanup", english: "Review Safe Cleanup")
        static let storageTotalCapacity = Self(key: "storage.total-capacity", english: "Total Capacity")
        static let storageUsed = Self(key: "storage.used", english: "Used")
    }
    static let allKeys: Set<String> = [
        "category.ai-data", "category.application", "category.cache", "category.conversation",
        "category.developer", "category.log", "category.model", "category.personal",
        "category.plugin", "category.skill", "category.system", "category.unclassified",
        "common.cancel", "common.location", "common.management", "common.risk", "common.scan",
        "common.skills", "common.space", "common.version", "nav.applications",
        "nav.cleanup-history", "nav.developer-ai", "nav.overview", "nav.storage",
        "plugins.discovery-failed", "plugins.empty", "plugins.official-handoff", "plugins.title",
        "risk.managed", "risk.rebuildable", "risk.safe", "risk.sensitive", "state.no-data",
        "state.preparing-summary",
        "ai.basic-footprint", "ai.data-items", "ai.deep-analysis", "ai.developer-storage",
        "ai.local-footprint", "ai.manage-in", "ai.no-content-indexed", "ai.plugins-managed",
        "ai.privacy", "ai.searching", "ai.section", "ai.select-application",
        "ai.skills-visible", "ai.storage-breakdown", "ai.total-indexed-space",
        "app.application", "app.association-confidence",
        "app.evidence.bundle-id", "app.evidence.container-id", "app.evidence.known-rule",
        "app.evidence.name", "app.evidence.signed-helper", "app.only-high-confidence",
        "app.ownership.owned", "app.ownership.possible", "app.ownership.shared",
        "app.related", "app.reset", "app.review-reset", "app.review-uninstall",
        "app.search-applications", "app.total-space",
        "app.uninstall", "cleanup.clear-selection", "cleanup.confirm-sensitive", "cleanup.confirm-trash",
        "cleanup.history-empty", "cleanup.history-empty-description", "cleanup.move-selected-trash",
        "cleanup.move-trash", "cleanup.moved-count", "cleanup.moving", "cleanup.review",
        "cleanup.review-description", "cleanup.select-all", "cleanup.selected-summary", "cleanup.summary.failed",
        "cleanup.summary.partial", "cleanup.summary.success", "cleanup.verified-space",
        "common.application-name", "common.category", "common.data", "common.item-count",
        "common.items", "common.name",
        "common.plugin", "common.related", "common.reveal-finder", "common.search-current",
        "common.skill", "common.source", "confidence.high", "confidence.low", "confidence.medium",
        "error.quit-before-uninstall", "error.reset-unavailable", "overview.analyze-mac",
        "overview.analyzed-categories-chart", "overview.analyzed-categories-description",
        "overview.analyzed-categories-empty", "overview.analyzed-locally", "overview.disk-available",
        "overview.disk-capacity-chart", "overview.disk-capacity-unavailable-description",
        "overview.disk-total", "overview.disk-used", "overview.internal-disk-used", "overview.limited-coverage",
        "overview.limited-coverage-description", "overview.no-recommendations", "overview.review-cleanup",
        "overview.safe-recommendations", "overview.start-scan", "overview.storage-glance",
        "overview.works-locally", "plugins.diagnostic-empty-skill", "plugins.diagnostic-generic",
        "plugins.diagnostic-invalid-manifest", "plugins.diagnostic-missing-manifest",
        "plugins.diagnostic-path-inaccessible",
        "scan.cancelled", "scan.completed", "scan.indexing", "scan.quick-inventory", "scan.ready",
        "scan.targeted-analysis", "settings.diagnostics", "settings.diagnostics-description",
        "settings.disk-access", "settings.disk-access-description", "settings.export-diagnostics",
        "settings.open-disk-access", "settings.privacy", "settings.privacy-description",
        "skill.scope.plugin", "skill.scope.shared", "skill.scope.system", "skill.status.parent-managed",
        "skill.status.read-only", "skill.status.standalone", "storage.all-analyzed",
        "storage.available", "storage.categories", "storage.internal-disk", "storage.largest",
        "storage.largest-items", "storage.no-matching", "storage.no-matching-description",
        "storage.old-items", "storage.older-180", "storage.review-safe-cleanup",
        "storage.total-capacity", "storage.used", "storage.used-of", "storage.visible-items",
        "cleanup.outcome.failed", "cleanup.outcome.moved",
        "cleanup.outcome.skipped-changed", "cleanup.outcome.skipped-protected",
        "cleanup.reason.changed-identity", "cleanup.reason.missing-source",
        "cleanup.reason.move-failed", "cleanup.reason.permission-denied",
        "cleanup.reason.protected-path", "cleanup.source-path",
        "explanation.application-bundle", "explanation.application-name-match",
        "explanation.claude-cache", "explanation.claude-conversation", "explanation.claude-logs",
        "explanation.claude-settings", "explanation.codex-cache", "explanation.codex-configuration",
        "explanation.codex-conversation", "explanation.codex-logs", "explanation.exact-bundle-match",
        "explanation.found-under", "explanation.gradle-cache", "explanation.homebrew-cache",
        "explanation.npm-cache", "explanation.pip-cache", "explanation.recognized-root",
        "explanation.simulator-data", "explanation.xcode-archives", "explanation.xcode-build",
        "cleanup.message.changed", "cleanup.message.moved", "cleanup.message.outside-volume",
        "cleanup.message.refusing-broad", "cleanup.message.refusing-system"
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

    private static func format(
        _ key: String,
        default defaultValue: String,
        locale: Locale?,
        _ arguments: CVarArg...
    ) -> String {
        String(format: value(key, default: defaultValue, locale: locale), locale: locale ?? .current, arguments: arguments)
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

    static func title(for destination: NavigationDestination, locale: Locale? = nil) -> String {
        switch destination {
        case .overview: overview(locale: locale)
        case .storage: storage(locale: locale)
        case .applications: applications(locale: locale)
        case .developerAI: developerAI(locale: locale)
        case .history: cleanupHistory(locale: locale)
        }
    }

    static func title(for tab: AIApplicationTab, locale: Locale? = nil) -> String {
        switch tab {
        case .overview: overview(locale: locale)
        case .dataStorage: value("common.data", default: "Data & Storage", locale: locale)
        case .plugins: plugins(locale: locale)
        case .skills: skills(locale: locale)
        }
    }

    static func name(for category: ItemCategory, locale: Locale? = nil) -> String {
        switch category {
        case .application: categoryApplication(locale: locale)
        case .personal: categoryPersonal(locale: locale)
        case .developer: categoryDeveloper(locale: locale)
        case .aiData: categoryAIData(locale: locale)
        case .cache: categoryCache(locale: locale)
        case .log: categoryLog(locale: locale)
        case .conversation: categoryConversation(locale: locale)
        case .model: categoryModel(locale: locale)
        case .plugin: categoryPlugin(locale: locale)
        case .skill: categorySkill(locale: locale)
        case .system: categorySystem(locale: locale)
        case .unclassified: categoryUnclassified(locale: locale)
        }
    }

    static func name(for risk: RiskLevel, locale: Locale? = nil) -> String {
        switch risk {
        case .safe: riskSafe(locale: locale)
        case .rebuildable: riskRebuildable(locale: locale)
        case .sensitive: riskSensitive(locale: locale)
        case .managed: riskManaged(locale: locale)
        }
    }

    static func name(for ownership: AssociationOwnership, locale: Locale? = nil) -> String {
        switch ownership {
        case .owned:
            value("app.ownership.owned", default: "Application-owned", locale: locale)
        case .shared:
            value("app.ownership.shared", default: "Shared component", locale: locale)
        case .possible:
            value("app.ownership.possible", default: "Possible association", locale: locale)
        }
    }

    static func name(for scope: SkillScope, locale: Locale? = nil) -> String {
        switch scope {
        case .sharedAgents: value("skill.scope.shared", default: "Shared", locale: locale)
        case .agentSpecific(let agent): agent
        case .pluginProvided: value("skill.scope.plugin", default: "Plugin", locale: locale)
        case .systemManaged: value("skill.scope.system", default: "System", locale: locale)
        }
    }

    static func name(for status: SkillManagementStatus, locale: Locale? = nil) -> String {
        switch status {
        case .standalone: value("skill.status.standalone", default: "Standalone", locale: locale)
        case .parentManaged: value("skill.status.parent-managed", default: "Plugin managed", locale: locale)
        case .systemReadOnly: value("skill.status.read-only", default: "Read only", locale: locale)
        }
    }

    static func name(for evidence: AssociationEvidence, locale: Locale? = nil) -> String {
        switch evidence {
        case .exactBundleIdentifier: value("app.evidence.bundle-id", default: "Bundle identifier", locale: locale)
        case .exactContainerIdentifier: value("app.evidence.container-id", default: "Container identifier", locale: locale)
        case .knownRule: value("app.evidence.known-rule", default: "Known application rule", locale: locale)
        case .signedHelperRelationship: value("app.evidence.signed-helper", default: "Signed helper", locale: locale)
        case .vendorAndNameMatch: value("app.evidence.name", default: "Application name", locale: locale)
        }
    }

    static func name(for confidence: AssociationConfidence, locale: Locale? = nil) -> String {
        switch confidence {
        case .low: value("confidence.low", default: "Low", locale: locale)
        case .medium: value("confidence.medium", default: "Medium", locale: locale)
        case .high: value("confidence.high", default: "High", locale: locale)
        }
    }

    static func association(_ evidence: AssociationEvidence, confidence: AssociationConfidence, locale: Locale? = nil) -> String {
        format(
            "app.association-confidence",
            default: "%@ · %@ confidence",
            locale: locale,
            name(for: evidence, locale: locale),
            name(for: confidence, locale: locale)
        )
    }

    static func name(for summary: CleanupSummary, locale: Locale? = nil) -> String {
        switch summary {
        case .success: value("cleanup.summary.success", default: "Completed", locale: locale)
        case .partialFailure: value("cleanup.summary.partial", default: "Partially completed", locale: locale)
        case .failed: value("cleanup.summary.failed", default: "Not completed", locale: locale)
        }
    }

    static func name(for status: CleanupOutcomeStatus, locale: Locale? = nil) -> String {
        switch status {
        case .movedToTrash: value("cleanup.outcome.moved", default: "Moved to Trash", locale: locale)
        case .skippedChanged: value("cleanup.outcome.skipped-changed", default: "Skipped: changed", locale: locale)
        case .skippedProtected: value("cleanup.outcome.skipped-protected", default: "Skipped: protected", locale: locale)
        case .failed: value("cleanup.outcome.failed", default: "Failed", locale: locale)
        }
    }

    static func scanStatus(for stage: ScanStage?, locale: Locale? = nil) -> String {
        guard let stage else { return value("scan.ready", default: "Ready to scan", locale: locale) }
        return switch stage {
        case .quickInventory: value("scan.quick-inventory", default: "Scanning applications…", locale: locale)
        case .targetedAnalysis: value("scan.targeted-analysis", default: "Analyzing storage and AI data…", locale: locale)
        case .indexing: value("scan.indexing", default: "Saving local metadata index…", locale: locale)
        case .completed: value("scan.completed", default: "Scan complete", locale: locale)
        }
    }

    static func text(_ copy: Copy, locale: Locale? = nil) -> String {
        value(copy.key, default: copy.english, locale: locale)
    }

    static func manageIn(_ application: String, locale: Locale? = nil) -> String {
        format("ai.manage-in", default: "Manage in %@", locale: locale, application)
    }

    static func skillsVisible(to application: String, locale: Locale? = nil) -> String {
        format("ai.skills-visible", default: "Skills visible to %@", locale: locale, application)
    }

    static func reviewCleanup(_ space: String, locale: Locale? = nil) -> String {
        format("overview.review-cleanup", default: "Review %@ Cleanup", locale: locale, space)
    }

    static func itemCount(_ count: Int, locale: Locale? = nil) -> String {
        format("common.item-count", default: "%lld items", locale: locale, Int64(count))
    }

    static func selectedItems(_ count: Int, space: String, locale: Locale? = nil) -> String {
        format(
            "cleanup.selected-summary",
            default: "%lld selected · %@",
            locale: locale,
            Int64(count),
            space
        )
    }

    static func visibleItems(_ count: Int, locale: Locale? = nil) -> String {
        format("storage.visible-items", default: "%lld visible items", locale: locale, Int64(count))
    }

    static func usedSpace(_ used: String, total: String, locale: Locale? = nil) -> String {
        format("storage.used-of", default: "%@ of %@", locale: locale, used, total)
    }

    static func quitBeforeUninstall(_ application: String, locale: Locale? = nil) -> String {
        format("error.quit-before-uninstall", default: "Quit %@ before uninstalling it.", locale: locale, application)
    }

    static func resetUnavailable(_ application: String, locale: Locale? = nil) -> String {
        format("error.reset-unavailable", default: "No high-confidence settings or caches are available to reset for %@.", locale: locale, application)
    }

    static func movedCount(_ count: Int, locale: Locale? = nil) -> String {
        format("cleanup.moved-count", default: "%lld moved", locale: locale, Int64(count))
    }

    static func verifiedSpace(_ space: String, locale: Locale? = nil) -> String {
        format("cleanup.verified-space", default: "%@ verified", locale: locale, space)
    }

    static func cleanupSourcePath(locale: Locale? = nil) -> String {
        value("cleanup.source-path", default: "Source path", locale: locale)
    }

    static func explanation(_ source: String, locale: Locale? = nil) -> String {
        let exact: [String: (String, String)] = [
            "Application bundle": ("explanation.application-bundle", "Application bundle"),
            "Application name match in a known service directory": ("explanation.application-name-match", "Application name match in a known service directory"),
            "Claude project conversation data": ("explanation.claude-conversation", "Claude project conversation data"),
            "Claude diagnostic logs": ("explanation.claude-logs", "Claude diagnostic logs"),
            "Claude rebuildable cache": ("explanation.claude-cache", "Claude rebuildable cache"),
            "Claude settings": ("explanation.claude-settings", "Claude settings"),
            "Codex conversation history": ("explanation.codex-conversation", "Codex conversation history"),
            "Codex diagnostic logs": ("explanation.codex-logs", "Codex diagnostic logs"),
            "Codex rebuildable cache": ("explanation.codex-cache", "Codex rebuildable cache"),
            "Codex configuration": ("explanation.codex-configuration", "Codex configuration"),
            "Xcode build products and indexes": ("explanation.xcode-build", "Xcode build products and indexes"),
            "Xcode release archives": ("explanation.xcode-archives", "Xcode release archives"),
            "Simulator runtimes and device data": ("explanation.simulator-data", "Simulator runtimes and device data"),
            "npm download cache": ("explanation.npm-cache", "npm download cache"),
            "Gradle dependency cache": ("explanation.gradle-cache", "Gradle dependency cache"),
            "Homebrew download cache": ("explanation.homebrew-cache", "Homebrew download cache"),
            "Python pip download cache": ("explanation.pip-cache", "Python pip download cache")
        ]
        if let translation = exact[source] {
            return value(translation.0, default: translation.1, locale: locale)
        }
        if source.hasPrefix("Found under ") {
            return format("explanation.found-under", default: "Found under %@", locale: locale, String(source.dropFirst(12)))
        }
        if source.hasPrefix("Exact bundle identifier match: ") {
            return format("explanation.exact-bundle-match", default: "Exact bundle identifier match: %@", locale: locale, String(source.dropFirst(31)))
        }
        let recognizedPrefix = "Recognized "
        let recognizedSuffix = " data root; contents were not indexed"
        if source.hasPrefix(recognizedPrefix), source.hasSuffix(recognizedSuffix) {
            let name = source.dropFirst(recognizedPrefix.count).dropLast(recognizedSuffix.count)
            return format("explanation.recognized-root", default: "Recognized %@ data root; contents were not indexed", locale: locale, String(name))
        }
        return source
    }

    static func cleanupOutcomeMessage(
        _ message: String,
        status: CleanupOutcomeStatus,
        locale: Locale? = nil
    ) -> String {
        if status == .movedToTrash, message == "Moved to Trash" {
            return value("cleanup.message.moved", default: "Moved to Trash", locale: locale)
        }
        if status == .skippedChanged, message == "File changed after the scan and was not moved" {
            return value(
                "cleanup.message.changed",
                default: "File changed after the scan and was not moved",
                locale: locale
            )
        }
        guard status == .skippedProtected else { return message }
        let knownPrefixes: [(prefix: String, key: String, fallback: String)] = [
            ("Refusing broad path: ", "cleanup.message.refusing-broad", "Refusing broad path: %@"),
            ("Refusing protected system path: ", "cleanup.message.refusing-system", "Refusing protected system path: %@"),
            ("Path is outside the allowed internal volume: ", "cleanup.message.outside-volume", "Path is outside the allowed internal volume: %@")
        ]
        for known in knownPrefixes where message.hasPrefix(known.prefix) {
            return format(
                known.key,
                default: known.fallback,
                locale: locale,
                String(message.dropFirst(known.prefix.count))
            )
        }
        return message
    }

    static func cleanupOutcomeMessage(
        _ outcome: CleanupOutcome,
        locale: Locale? = nil
    ) -> String {
        guard let reason = outcome.reason else {
            return cleanupOutcomeMessage(outcome.message, status: outcome.status, locale: locale)
        }
        return switch reason {
        case .moved:
            value("cleanup.message.moved", default: "Moved to Trash", locale: locale)
        case .changedIdentity:
            value(
                "cleanup.reason.changed-identity",
                default: "The item changed after the scan and was not moved.",
                locale: locale
            )
        case .missingSource:
            value(
                "cleanup.reason.missing-source",
                default: "The item no longer exists at the source path.",
                locale: locale
            )
        case .protectedPath:
            value(
                "cleanup.reason.protected-path",
                default: "The source path is protected and was not moved.",
                locale: locale
            )
        case .permissionDenied:
            value(
                "cleanup.reason.permission-denied",
                default: "Permission was denied while moving the item to Trash.",
                locale: locale
            )
        case .moveFailed:
            value(
                "cleanup.reason.move-failed",
                default: "The item could not be moved to Trash.",
                locale: locale
            )
        }
    }
}
