import AppKit
import SwiftUI

@main
struct SpacePilotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            AppWindowContent(
                model: model,
                onWindowAvailable: appDelegate.registerMainWindow
            )
#if DEBUG
                .preferredColorScheme(
                    ProcessInfo.processInfo.environment["SPACEPILOT_FORCE_DARK"] == "1" ? .dark : nil
                )
#endif
                .task {
                    appDelegate.configure(model: model)
                }
        }
        .defaultSize(width: 1_180, height: 760)

        Settings {
            SettingsView(model: model)
        }
    }
}

struct AppWindowContent: View {
    @Bindable var model: AppModel
    var onWindowAvailable: ((NSWindow) -> Void)? = nil

    var body: some View {
        AppRootView(model: model)
            .background {
                MainWindowRegistrationView(onWindowAvailable: onWindowAvailable)
                    .frame(width: 0, height: 0)
            }
    }
}

private struct MainWindowRegistrationView: NSViewRepresentable {
    let onWindowAvailable: ((NSWindow) -> Void)?

    func makeNSView(context: Context) -> MainWindowRegistrationNSView {
        MainWindowRegistrationNSView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: MainWindowRegistrationNSView, context: Context) {
        nsView.onWindowAvailable = onWindowAvailable
        nsView.reportWindowIfAvailable()
    }
}

private final class MainWindowRegistrationNSView: NSView {
    var onWindowAvailable: ((NSWindow) -> Void)?

    init(onWindowAvailable: ((NSWindow) -> Void)?) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindowIfAvailable()
    }

    func reportWindowIfAvailable() {
        guard let window else { return }
        onWindowAvailable?(window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let iconController = ApplicationIconController()
    private let dynamicIslandController = DynamicIslandController()

    func configure(model: AppModel) {
        dynamicIslandController.configure(model: model)
    }

    func registerMainWindow(_ window: NSWindow) {
        dynamicIslandController.registerMainWindow(window)
    }

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

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        dynamicIslandController.presentCurrentMode()
        return false
    }
}
