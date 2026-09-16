import Foundation
import XCTest
@testable import SpacePilotCore

final class RegisteredApplicationDiscoveryTests: XCTestCase {
    func testKeepsInstalledSupportAppsAndRejectsBuildArtifactsAndNestedHelpers() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let candidates = [
            "/Applications/TeX/TeXShop.app",
            "/Users/example/Library/Application Support/Google/GoogleUpdater/1/GoogleUpdater.app",
            "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
            "/Users/example/anaconda3/Anaconda-Navigator.app",
            "/Applications/Editor.app/Contents/Frameworks/Editor Helper.app",
            "/Users/example/Library/Developer/Xcode/DerivedData/App/Build/Products/App.app",
            "/Users/example/AI/Project/dist/Project.app",
            "/Library/Application Support/Script Editor/Templates/Droplets/Template.app"
        ].map { URL(fileURLWithPath: $0) }
        let discovery = RegisteredApplicationDiscovery(
            homeDirectory: home,
            query: { candidates }
        )

        let result = discovery.applicationURLs().map(\.path)

        XCTAssertEqual(Set(result), [
            "/Applications/TeX/TeXShop.app",
            "/Users/example/Library/Application Support/Google/GoogleUpdater/1/GoogleUpdater.app",
            "/Library/Application Support/Microsoft/MAU2.0/Microsoft AutoUpdate.app",
            "/Users/example/anaconda3/Anaconda-Navigator.app"
        ])
    }

    func testRejectsAppsNestedInsideNonAppBundleContainers() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        // 这些 .app 都嵌套在其他应用/工具沙箱内部的 macOS bundle 容器里
        // (.framework 自带解释器 stub、Helper),不是独立安装的应用。
        let candidates = [
            "/Users/example/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/vm/tools/opt/python@3.10/3.10.20_3/Frameworks/Python.framework/Versions/3.10/Resources/Python.app",
            "/Users/example/Library/Application Support/LarkShell/update/update.noindex/Lark.app/Contents/Frameworks/Lark Framework.framework/Versions/147.0.7727.149/Helpers/Lark Helper.app",
            "/Users/example/Library/Application Support/Vendor/Plugins/Sample.plugin/Contents/Sample.app",
            "/Users/example/Library/Application Support/Vendor/Extensions/Share.appex/Contents/Share.app",
            "/Users/example/Library/Application Support/TeXShop.app"
        ].map { URL(fileURLWithPath: $0) }
        let discovery = RegisteredApplicationDiscovery(
            homeDirectory: home,
            query: { candidates }
        )

        let result = discovery.applicationURLs().map(\.path)

        // 只有未嵌套在任何 bundle 容器内的真实应用被保留。
        XCTAssertEqual(result, [
            "/Users/example/Library/Application Support/TeXShop.app"
        ])
    }

    func testRejectsAppsInsideEmbeddedHomebrewToolchain() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        // TRAE SOLO CN 把整套 Homebrew 环境内嵌进自身沙箱,其 opt/<formula>
        // 与 Cellar 布局下的 .app 是 formula 组件(Python/IDLE/Launcher),
        // 直接位于版本目录下、未嵌套在 bundle 容器内,不能当作已安装应用。
        let candidates = [
            "/Users/example/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/vm/tools/opt/python@3.10/3.10.20_3/IDLE 3.app",
            "/Users/example/Library/Application Support/TRAE SOLO CN/ModularData/ai-agent/vm/tools/opt/python@3.10/3.10.20_3/Python Launcher 3.app",
            "/Users/example/Library/Application Support/Vendor/Cellar/python@3.12/3.12.1/IDLE 3.app",
            "/Users/example/Library/Application Support/RealApp.app"
        ].map { URL(fileURLWithPath: $0) }
        let discovery = RegisteredApplicationDiscovery(
            homeDirectory: home,
            query: { candidates }
        )

        let result = discovery.applicationURLs().map(\.path)

        XCTAssertEqual(result, [
            "/Users/example/Library/Application Support/RealApp.app"
        ])
    }
}
