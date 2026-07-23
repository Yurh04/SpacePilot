import Foundation
import SpacePilotCore
import XCTest
@testable import SpacePilot

final class LocalizationTests: XCTestCase {
    func testNavigationAndPluginLabelsUseEnglishAndSimplifiedChinese() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")

        XCTAssertEqual(L10n.title(for: NavigationDestination.storage, locale: english), "Storage")
        XCTAssertEqual(L10n.title(for: NavigationDestination.storage, locale: chinese), "储存空间")
        XCTAssertEqual(L10n.title(for: AIApplicationTab.plugins, locale: english), "Plugins")
        XCTAssertEqual(L10n.title(for: AIApplicationTab.plugins, locale: chinese), "插件")
    }

    func testScanStagesUseEnglishAndSimplifiedChinese() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")

        XCTAssertEqual(L10n.scanStatus(for: .quickInventory, locale: english), "Scanning applications…")
        XCTAssertEqual(L10n.scanStatus(for: .quickInventory, locale: chinese), "正在扫描应用程序…")
        XCTAssertEqual(L10n.scanStatus(for: .completed, locale: english), "Scan complete")
        XCTAssertEqual(L10n.scanStatus(for: .completed, locale: chinese), "扫描完成")
    }

    func testEveryDisplayEnumHasEnglishAndSimplifiedChineseText() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")

        for category in ItemCategory.allCases {
            XCTAssertFalse(L10n.name(for: category, locale: english).isEmpty)
            XCTAssertFalse(L10n.name(for: category, locale: chinese).isEmpty)
        }
        for risk in RiskLevel.allCases {
            XCTAssertFalse(L10n.name(for: risk, locale: english).isEmpty)
            XCTAssertFalse(L10n.name(for: risk, locale: chinese).isEmpty)
        }
        XCTAssertEqual(L10n.name(for: SkillScope.sharedAgents, locale: english), "Shared")
        XCTAssertEqual(L10n.name(for: SkillScope.sharedAgents, locale: chinese), "共享")
        XCTAssertEqual(L10n.name(for: SkillManagementStatus.systemReadOnly, locale: english), "Read only")
        XCTAssertEqual(L10n.name(for: SkillManagementStatus.systemReadOnly, locale: chinese), "只读")
    }

    func testKnownScannerExplanationsAreLocalizedAtPresentationTime() {
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(L10n.explanation("Codex conversation history", locale: chinese), "Codex 对话历史")
        XCTAssertEqual(L10n.explanation("Found under Downloads", locale: chinese), "在 Downloads 下发现")
        XCTAssertEqual(
            L10n.explanation("Recognized ChatGPT data root; contents were not indexed", locale: chinese),
            "已识别 ChatGPT 数据根目录；未索引其中内容"
        )
    }

    func testCleanupOutcomeReasonsLocalizeKnownMessagesAndPreserveUnknownErrors() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")
        XCTAssertEqual(
            L10n.cleanupOutcomeMessage(
                "File changed after the scan and was not moved",
                status: .skippedChanged,
                locale: chinese
            ),
            "文件在扫描后发生变化，因此未移动"
        )
        XCTAssertEqual(
            L10n.cleanupOutcomeMessage("Refusing protected system path: /System/Test", status: .skippedProtected, locale: chinese),
            "拒绝受保护的系统路径：/System/Test"
        )
        XCTAssertEqual(
            L10n.cleanupOutcomeMessage("Moved to Trash", status: .movedToTrash, locale: english),
            "Moved to Trash"
        )
        XCTAssertEqual(
            L10n.cleanupOutcomeMessage("NSCocoaErrorDomain 513", status: .failed, locale: chinese),
            "NSCocoaErrorDomain 513"
        )
    }

    func testCleanupOutcomeContextAndReasonsUseEnglishAndSimplifiedChinese() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")

        XCTAssertEqual(L10n.cleanupSourcePath(locale: english), "Source path")
        XCTAssertEqual(L10n.cleanupSourcePath(locale: chinese), "源路径")

        let expected: [(CleanupOutcomeReason, String, String)] = [
            (.changedIdentity, "The item changed after the scan and was not moved.", "项目在扫描后发生变化，因此未移动。"),
            (.missingSource, "The item no longer exists at the source path.", "源路径中的项目已不存在。"),
            (.protectedPath, "The source path is protected and was not moved.", "源路径受保护，因此未移动。"),
            (.permissionDenied, "Permission was denied while moving the item to Trash.", "将项目移到废纸篓时权限被拒绝。"),
            (.moveFailed, "The item could not be moved to Trash.", "无法将项目移到废纸篓。")
        ]

        for (reason, englishMessage, chineseMessage) in expected {
            let outcome = CleanupOutcome(
                candidateID: UUID(),
                status: reason == .changedIdentity || reason == .missingSource ? .skippedChanged : .failed,
                resultingURL: nil,
                message: "Raw implementation error",
                reason: reason
            )
            XCTAssertEqual(L10n.cleanupOutcomeMessage(outcome, locale: english), englishMessage)
            XCTAssertEqual(L10n.cleanupOutcomeMessage(outcome, locale: chinese), chineseMessage)
        }
    }

    func testEveryDisplayMappingHasEnglishAndSimplifiedChineseText() {
        let locales = [Locale(identifier: "en"), Locale(identifier: "zh-Hans")]
        let scopes: [SkillScope] = [
            .sharedAgents, .agentSpecific(agent: "Codex"),
            .pluginProvided(pluginID: "plugin"), .systemManaged
        ]
        let managementStatuses: [SkillManagementStatus] = [.standalone, .parentManaged, .systemReadOnly]
        let evidences: [AssociationEvidence] = [
            .exactBundleIdentifier, .exactContainerIdentifier, .knownRule,
            .signedHelperRelationship, .vendorAndNameMatch
        ]
        let confidences: [AssociationConfidence] = [.low, .medium, .high]
        let summaries: [CleanupSummary] = [.success, .partialFailure, .failed]
        let outcomeStatuses: [CleanupOutcomeStatus] = [
            .movedToTrash, .skippedChanged, .skippedProtected, .failed
        ]

        for locale in locales {
            XCTAssertTrue(scopes.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(managementStatuses.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(evidences.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(confidences.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(summaries.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(outcomeStatuses.allSatisfy { !L10n.name(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(AIApplicationTab.allCases.allSatisfy { !L10n.title(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(NavigationDestination.allCases.allSatisfy { !L10n.title(for: $0, locale: locale).isEmpty })
            XCTAssertTrue(ScanStage.allCases.allSatisfy { !L10n.scanStatus(for: $0, locale: locale).isEmpty })
        }
    }

    func testNavigationUsesEnglishAndSimplifiedChinese() {
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "en")), "Overview")
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "zh-Hans")), "概览")
        XCTAssertEqual(L10n.developerAI(locale: Locale(identifier: "zh-Hans")), "开发与 AI")
    }

    func testPluginEmptyStatesAreTranslated() {
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "en")), "No Plugins installed")
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "zh-Hans")), "未安装插件")
    }

    func testSelectiveCleanupAndStorageWorkbenchUseBothLanguages() {
        let english = Locale(identifier: "en")
        let chinese = Locale(identifier: "zh-Hans")

        XCTAssertEqual(L10n.text(.cleanupSelectAll, locale: english), "Select All")
        XCTAssertEqual(L10n.text(.cleanupSelectAll, locale: chinese), "全选")
        XCTAssertEqual(
            L10n.text(.storageAllAnalyzed, locale: english),
            "All Analyzed Items"
        )
        XCTAssertEqual(
            L10n.text(.storageAllAnalyzed, locale: chinese),
            "全部已分析项目"
        )
        XCTAssertEqual(
            L10n.selectedItems(2, space: "3 GB", locale: chinese),
            "已选 2 项，共 3 GB"
        )
        XCTAssertEqual(
            L10n.usedSpace("420 GB", total: "500 GB", locale: english),
            "420 GB of 500 GB"
        )
        XCTAssertEqual(L10n.itemCount(8, locale: chinese), "8 项")
        XCTAssertEqual(L10n.visibleItems(5, locale: chinese), "显示 5 项")
    }

    func testPluginDiagnosticsAreSpecificLocalizedAndSanitizedForPresentation() {
        let privatePath = "/Users/private/.codex/plugins/cache/source/plugin/1.0.0"
        let diagnostics = [
            PluginDiscoveryDiagnostic.cacheInaccessible.message,
            "Missing Plugin manifest at \(privatePath)/.codex-plugin/plugin.json",
            "Invalid Plugin manifest at \(privatePath)/.codex-plugin/plugin.json: private detail"
        ]

        let english = PluginDiagnosticPresentation.summaries(
            diagnostics,
            locale: Locale(identifier: "en")
        )
        let chinese = PluginDiagnosticPresentation.summaries(
            diagnostics,
            locale: Locale(identifier: "zh-Hans")
        )

        XCTAssertEqual(english, [
            "A Plugin path could not be accessed.",
            "A Plugin manifest could not be found.",
            "A Plugin manifest could not be read."
        ])
        XCTAssertEqual(chinese, [
            "无法访问插件路径。",
            "找不到某个插件清单。",
            "无法读取某个插件清单。"
        ])
        XCTAssertFalse((english + chinese).contains { $0.contains(privatePath) })
    }

    func testLocalizationBundleContainsEnglishAndSimplifiedChinese() {
        XCTAssertTrue(
            L10n.availableLocalizations.contains("en"),
            "Available localizations: \(L10n.availableLocalizations)"
        )
        XCTAssertTrue(
            L10n.availableLocalizations.contains("zh-Hans"),
            "Available localizations: \(L10n.availableLocalizations)"
        )
    }

    func testPreferredLanguagesNegotiateAgainstSupportedLocalizations() {
        XCTAssertEqual(
            L10n.negotiatedLocalization(preferredLanguages: ["fr", "zh-Hans", "en"]),
            "zh-Hans"
        )
    }

    func testCatalogAndRuntimeTablesContainTheSameKeysAndValues() throws {
        let resources = repositoryRoot.appending(path: "Sources/SpacePilot/Resources")
        let catalogData = try Data(contentsOf: resources.appending(path: "Localizable.xcstrings"))
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let catalogStrings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let english = try stringsTable(at: resources.appending(path: "en.lproj/Localizable.strings"))
        let chinese = try stringsTable(at: resources.appending(path: "zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(L10n.allKeys.count, 183)
        XCTAssertEqual(Set(catalogStrings.keys), L10n.allKeys)
        XCTAssertEqual(Set(english.keys), L10n.allKeys)
        XCTAssertEqual(Set(chinese.keys), L10n.allKeys)

        for key in L10n.allKeys {
            let entry = try XCTUnwrap(catalogStrings[key] as? [String: Any])
            let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any])
            XCTAssertEqual(try catalogValue(in: localizations, locale: "en"), english[key], key)
            XCTAssertEqual(try catalogValue(in: localizations, locale: "zh-Hans"), chinese[key], key)
        }
    }

    func testStageOnlyBuildsSignedAppWithLocalizationResources() throws {
        let script = repositoryRoot.appending(path: "script/build_and_run.sh")
        let testRoot = FileManager.default.temporaryDirectory
            .appending(path: "SpacePilotLocalizationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: testRoot) }
        let dist = testRoot.appending(path: "dist", directoryHint: .isDirectory)
        let stageResult = try run(
            script,
            arguments: ["--stage-only"],
            environment: [
                "SPACEPILOT_DIST_DIR": dist.path,
                "SPACEPILOT_SCRATCH_PATH": testRoot.appending(path: "build").path
            ]
        )
        XCTAssertEqual(stageResult.status, 0, stageResult.output)

        let app = dist.appending(path: "SpacePilot.app")
        let appResources = app.appending(path: "Contents/Resources")
        let candidates = try FileManager.default.contentsOfDirectory(
            at: appResources,
            includingPropertiesForKeys: [.isDirectoryKey]
        ).filter {
            $0.pathExtension == "bundle" && $0.lastPathComponent.hasPrefix("SpacePilot_")
        }
        let resourceBundle = try XCTUnwrap(candidates.only)
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourceBundle.appending(path: "en.lproj").path))
        let localizedDirectories = try FileManager.default.contentsOfDirectory(
            at: resourceBundle,
            includingPropertiesForKeys: [.isDirectoryKey]
        )
        XCTAssertTrue(localizedDirectories.contains {
            $0.lastPathComponent.caseInsensitiveCompare("zh-Hans.lproj") == .orderedSame
        })

        let signResult = try run(
            URL(fileURLWithPath: "/usr/bin/codesign"),
            arguments: ["--verify", "--deep", "--strict", app.path]
        )
        XCTAssertEqual(signResult.status, 0, signResult.output)

        let builtBundle = try XCTUnwrap(resourceBundles(below: testRoot.appending(path: "build")).only)
        let unexpectedBundle = builtBundle.deletingLastPathComponent()
            .appending(path: "SpacePilot_Unexpected.bundle", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: unexpectedBundle, withIntermediateDirectories: false)
        let ambiguousResult = try run(
            script,
            arguments: ["--stage-only"],
            environment: [
                "SPACEPILOT_DIST_DIR": dist.path,
                "SPACEPILOT_SCRATCH_PATH": testRoot.appending(path: "build").path
            ]
        )
        XCTAssertNotEqual(ambiguousResult.status, 0)
        XCTAssertTrue(ambiguousResult.output.contains("Expected exactly one"), ambiguousResult.output)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func stringsTable(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        )
    }

    private func catalogValue(in localizations: [String: Any], locale: String) throws -> String {
        let localization = try XCTUnwrap(localizations[locale] as? [String: Any])
        let stringUnit = try XCTUnwrap(localization["stringUnit"] as? [String: Any])
        return try XCTUnwrap(stringUnit["value"] as? String)
    }

    private func resourceBundles(below root: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        )
        return enumerator.compactMap { element in
            guard let url = element as? URL,
                  url.pathExtension == "bundle",
                  url.lastPathComponent.hasPrefix("SpacePilot_") else {
                return nil
            }
            enumerator.skipDescendants()
            return url
        }
    }

    private func run(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

private extension Collection {
    var only: Element? {
        count == 1 ? first : nil
    }
}
