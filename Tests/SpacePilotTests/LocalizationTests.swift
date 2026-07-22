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

    func testPreferredLanguagesNegotiateAgainstSupportedLocalizations() {
        XCTAssertEqual(
            L10n.negotiatedLocalization(preferredLanguages: ["fr", "zh-Hans", "en"]),
            "zh-Hans"
        )
    }

    func testCatalogAndRuntimeTablesContainTheSameThirtyFiveKeysAndValues() throws {
        let resources = repositoryRoot.appending(path: "Sources/SpacePilot/Resources")
        let catalogData = try Data(contentsOf: resources.appending(path: "Localizable.xcstrings"))
        let catalog = try XCTUnwrap(
            JSONSerialization.jsonObject(with: catalogData) as? [String: Any]
        )
        let catalogStrings = try XCTUnwrap(catalog["strings"] as? [String: Any])
        let english = try stringsTable(at: resources.appending(path: "en.lproj/Localizable.strings"))
        let chinese = try stringsTable(at: resources.appending(path: "zh-Hans.lproj/Localizable.strings"))

        XCTAssertEqual(L10n.allKeys.count, 35)
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
