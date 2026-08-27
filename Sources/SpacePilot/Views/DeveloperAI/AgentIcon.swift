import AppKit
import SpacePilotCore
import SwiftUI

/// Renders an `AgentIconDescriptor` produced by the Core layer. This is the only
/// place that resolves an Agent icon into an image: the Core layer expresses
/// precedence (installed application icon > bundled asset > SF Symbol) and never
/// imports AppKit, loads an image, or reads a URL from a manifest.
///
/// - `.installedApplication(url)` reads the real, cached file icon via
///   `NSWorkspace` (reusing `FileIconCache`).
/// - `.bundledAsset(name)` uses a code-owned asset shipped in the app bundle,
///   falling back safely to a symbol if the asset is missing.
/// - `.systemSymbol(name)` renders an SF Symbol.
///
/// The frame size and corner radius are fixed so list and detail icons stay
/// visually stable regardless of the underlying source.
struct AgentIcon: View {
    let descriptor: AgentIconDescriptor
    var size: CGFloat = 20

    var body: some View {
        image
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        switch descriptor {
        case .installedApplication(let url):
            Image(nsImage: FileIconCache.shared.image(for: url))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .bundledAsset(let name):
            if let bundled = NSImage(named: name) {
                Image(nsImage: bundled)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Safe fallback when a bundled asset is not present in the app.
                Image(systemName: "sparkles")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
            }
        case .systemSymbol(let name):
            Image(systemName: name)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.secondary)
        }
    }
}
