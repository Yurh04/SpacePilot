import AppKit
import OSLog

/// Keeps the running Dock icon in sync with the application's effective system appearance.
/// The compiled Icon Composer asset handles Finder and the non-running app on macOS 26+.
@MainActor
final class ApplicationIconController {
    private let logger = Logger(subsystem: "com.yurunhao.SpacePilot", category: "AppIcon")
    private var observation: NSKeyValueObservation?
    private let apply: (NSImage) -> Void
    private let light: NSImage?
    private let dark: NSImage?

    private static func loadDockImage(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = NSImage(contentsOf: url) else { return nil }
        return dockImage(source)
    }

    /// Icon Composer exports a tight tile; applicationIconImage expects the complete
    /// canvas, including the transparent margin supplied by the system for bundle icons.
    private static func dockImage(_ source: NSImage) -> NSImage {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: NSRect(x: 100, y: 100, width: 824, height: 824),
                    from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        return image
    }

    init(apply: @escaping (NSImage) -> Void = { NSApp.applicationIconImage = $0 }) {
        self.apply = apply
        light = Self.loadDockImage(named: "AppIcon-Light")
        dark = Self.loadDockImage(named: "AppIcon-Dark")
    }

    func start(application: NSApplication) {
        stop()
        update(application.effectiveAppearance)
        observation = application.observe(\.effectiveAppearance, options: [.new]) { [weak self] application, _ in
            Task { @MainActor [weak self, weak application] in
                guard let self, self.observation != nil, let application else { return }
                self.update(application.effectiveAppearance)
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
    }

    private func update(_ appearance: NSAppearance) {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard let image = isDark ? dark : light else {
            logger.error("Application icon resource missing")
            return
        }
        apply(image)
        logger.notice("Applied application icon: \(isDark ? "dark" : "light", privacy: .public)")
    }
}
