import Foundation
import XCTest
@testable import SpacePilot

final class LocalizationTests: XCTestCase {
    func testNavigationUsesEnglishAndSimplifiedChinese() {
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "en")), "Overview")
        XCTAssertEqual(L10n.overview(locale: Locale(identifier: "zh-Hans")), "概览")
        XCTAssertEqual(L10n.developerAI(locale: Locale(identifier: "zh-Hans")), "开发与 AI")
    }

    func testPluginEmptyStatesAreTranslated() {
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "en")), "No Plugins installed")
        XCTAssertEqual(L10n.noPluginsInstalled(locale: Locale(identifier: "zh-Hans")), "未安装插件")
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

    func testBuildScriptStagesSwiftPMResourceBundleIntoAppResources() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let script = try String(
            contentsOf: repositoryRoot.appending(path: "script/build_and_run.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(script.contains("SpacePilot_SpacePilot.bundle"))
        XCTAssertTrue(script.contains("$APP_CONTENTS/Resources"))
        XCTAssertTrue(script.contains("cp -R \"$RESOURCE_BUNDLE\" \"$APP_RESOURCES/\""))
    }
}
