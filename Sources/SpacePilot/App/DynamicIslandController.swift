import AppKit
import SpacePilotCore
import SwiftUI

@MainActor
final class DynamicIslandController: NSObject {
    private enum Layout {
        static let collapsedSize = NSSize(width: 300, height: 48)
        static let expandedSize = NSSize(width: 360, height: 238)
        static let topInset: CGFloat = 4
    }

    private weak var mainWindow: NSWindow?
    private weak var model: AppModel?
    private var panel: NSPanel?
    private var isExpanded = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presentationModeDidChange),
            name: .spacePilotPresentationModeDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func presentationModeDidChange() {
        apply(.current)
    }

    @objc private func screenParametersDidChange() {
        repositionPanel(animated: false)
    }

    func configure(model: AppModel) {
        self.model = model
        apply(.current)
    }

    func registerMainWindow(_ window: NSWindow) {
        guard window !== panel else { return }
        mainWindow = window
        window.identifier = NSUserInterfaceItemIdentifier("SpacePilot.mainWindow")
        apply(.current)
    }

    func presentCurrentMode() {
        apply(.current)
    }

    private func apply(_ mode: AppPresentationMode) {
        guard let model else { return }
        switch mode {
        case .window:
            panel?.orderOut(nil)
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        case .dynamicIsland:
            mainWindow?.orderOut(nil)
            showPanel(model: model)
        }
    }

    private func showPanel(model: AppModel) {
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        repositionPanel(animated: false)
        panel.orderFrontRegardless()
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = DynamicIslandPanel(
            contentRect: NSRect(origin: .zero, size: Layout.collapsedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.identifier = NSUserInterfaceItemIdentifier("SpacePilot.dynamicIsland")
        panel.setAccessibilityLabel(L10n.text(.dynamicIslandTitle))
        panel.contentViewController = NSHostingController(
            rootView: DynamicIslandView(
                model: model,
                onExpansionChanged: { [weak self] expanded in
                    self?.setExpanded(expanded)
                },
                showFullWindow: {
                    AppPresentationMode.select(.window)
                }
            )
        )
        return panel
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        repositionPanel(animated: true)
    }

    private func repositionPanel(animated: Bool) {
        guard let panel else { return }
        let screen = mainWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let size = isExpanded ? Layout.expandedSize : Layout.collapsedSize
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - Layout.topInset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: animated)
    }
}

private final class DynamicIslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private struct DynamicIslandView: View {
    @Bindable var model: AppModel
    let onExpansionChanged: (Bool) -> Void
    let showFullWindow: () -> Void

    @State private var isExpanded = false

    var body: some View {
        Group {
            if isExpanded {
                expandedContent
            } else {
                collapsedContent
            }
        }
        .frame(width: isExpanded ? 360 : 300, height: isExpanded ? 238 : 48)
        .background(.black.opacity(0.94), in: RoundedRectangle(cornerRadius: isExpanded ? 28 : 24))
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? 28 : 24)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .foregroundStyle(.white)
        .animation(.snappy(duration: 0.24), value: isExpanded)
    }

    private var collapsedContent: some View {
        Button {
            setExpanded(true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.isScanning ? "arrow.triangle.2.circlepath" : "internaldrive.fill")
                    .symbolEffect(.rotate, isActive: model.isScanning)
                    .foregroundStyle(model.isScanning ? .blue : .green)
                Text(collapsedTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(.dynamicIslandExpand))
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            HStack {
                Label(L10n.text(.dynamicIslandTitle), systemImage: "internaldrive.fill")
                    .font(.headline)
                Spacer()
                Button {
                    setExpanded(false)
                } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text(.dynamicIslandCollapse))
            }

            if let overview = model.projection?.overview {
                HStack(spacing: 10) {
                    metric(
                        title: L10n.text(.overviewDiskAvailable),
                        value: overview.hasWholeDiskCapacity ? ByteCount.string(overview.availableBytes) : "—",
                        color: .green
                    )
                    metric(
                        title: L10n.text(.overviewSafeRecommendations),
                        value: ByteCount.string(overview.reclaimableBytes),
                        color: .blue
                    )
                }
            } else {
                ContentUnavailableView(
                    L10n.text(.dynamicIslandNoData),
                    systemImage: "internaldrive",
                    description: Text(L10n.text(.dynamicIslandNoDataDescription))
                )
                .frame(maxHeight: .infinity)
                .foregroundStyle(.white, .secondary)
            }

            if model.isScanning {
                ProgressView(value: model.scanProgress)
                    .tint(.blue)
                    .accessibilityLabel(model.scanMessage)
            }

            HStack(spacing: 10) {
                Button {
                    model.startScan(scope: .full)
                } label: {
                    Label(L10n.text(.overviewRescan), systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .disabled(model.isScanning)

                Button(action: showFullWindow) {
                    Label(L10n.text(.dynamicIslandShowWindow), systemImage: "macwindow")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(18)
    }

    private var collapsedTitle: String {
        if model.isScanning {
            return model.scanMessage
        }
        guard let overview = model.projection?.overview,
              overview.hasWholeDiskCapacity else {
            return L10n.text(.dynamicIslandNoData)
        }
        return "\(L10n.text(.overviewDiskAvailable)) · \(ByteCount.string(overview.availableBytes))"
    }

    private func metric(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func setExpanded(_ expanded: Bool) {
        isExpanded = expanded
        onExpansionChanged(expanded)
    }
}
