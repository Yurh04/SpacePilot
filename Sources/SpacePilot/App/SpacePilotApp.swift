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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        if ProcessInfo.processInfo.environment["SPACEPILOT_FORCE_DARK"] == "1" {
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
#endif
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
