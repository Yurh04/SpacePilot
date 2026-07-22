import AppKit
import SwiftUI

@main
struct SpacePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(model: model)
                .frame(minWidth: 1_000, minHeight: 680)
        }
        .defaultSize(width: 1_180, height: 760)

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("SpacePilot Settings")
                    .font(.title2.weight(.semibold))
                Text("Permissions and scan preferences will appear here.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(width: 460, height: 240, alignment: .topLeading)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
