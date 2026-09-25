import AppKit
import SwiftUI

@main
struct SpacePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppWindowContent(model: model)
#if DEBUG
                .preferredColorScheme(
                    ProcessInfo.processInfo.environment["SPACEPILOT_FORCE_DARK"] == "1" ? .dark : nil
                )
#endif
        }
        .defaultSize(width: 1_180, height: 760)

        Settings {
            SettingsView(model: model)
        }
    }
}

struct AppWindowContent: View {
    @Bindable var model: AppModel

    var body: some View {
        AppRootView(model: model)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let iconController = ApplicationIconController()

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if ProcessInfo.processInfo.environment["SPACEPILOT_FORCE_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
#endif
        NSApp.setActivationPolicy(.regular)
        iconController.start(application: NSApp)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        iconController.stop()
    }
}
