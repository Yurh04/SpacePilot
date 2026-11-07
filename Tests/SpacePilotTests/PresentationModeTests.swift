import AppKit
import XCTest
@testable import SpacePilot

@MainActor
final class PresentationModeTests: XCTestCase {
    private let defaultsKey = AppPresentationMode.defaultsKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        super.tearDown()
    }

    func testPresentationModeDefaultsToWindowAndRoundTrips() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        XCTAssertEqual(AppPresentationMode.current, .window)

        AppPresentationMode.select(.dynamicIsland)
        XCTAssertEqual(AppPresentationMode.current, .dynamicIsland)

        AppPresentationMode.select(.window)
        XCTAssertEqual(AppPresentationMode.current, .window)
    }

    func testDynamicIslandArchitectureKeepsAppKitAtTheWindowBoundary() throws {
        let source = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/SpacePilot/App/DynamicIslandController.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: repositoryRoot.appending(path: "Sources/SpacePilot/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(source.contains("styleMask: [.borderless, .nonactivatingPanel]"))
        XCTAssertTrue(source.contains("panel.level = .statusBar"))
        XCTAssertTrue(source.contains(".canJoinAllSpaces"))
        XCTAssertTrue(source.contains("screen.frame.midX"))
        XCTAssertTrue(source.contains("model.projection?.overview"))
        XCTAssertTrue(settings.contains("AppPresentationMode.select(mode)"))
    }

    func testControllerSwitchesBetweenMainWindowAndDynamicIslandPanel() throws {
        _ = NSApplication.shared
        let model = AppModel(
            runtime: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { _, _ in [] }
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1_180, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let controller = DynamicIslandController()
        AppPresentationMode.select(.window)
        controller.configure(model: model)
        controller.registerMainWindow(window)
        XCTAssertTrue(window.isVisible)

        AppPresentationMode.select(.dynamicIsland)
        let panel = try XCTUnwrap(NSApp.windows.first {
            $0.identifier?.rawValue == "SpacePilot.dynamicIsland"
        })
        XCTAssertFalse(window.isVisible)
        XCTAssertEqual(panel.level, .statusBar)
        XCTAssertEqual(panel.frame.size.width, 300, accuracy: 0.5)
        XCTAssertEqual(panel.frame.size.height, 48, accuracy: 0.5)
        XCTAssertTrue(panel.isVisible)

        AppPresentationMode.select(.window)
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(panel.isVisible)

        panel.close()
        window.close()
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
