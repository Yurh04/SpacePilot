import AppKit
import SwiftUI

/// Adds bounded, whole-row feedback without replacing native table behavior.
struct NativeTableHoverAdapter: NSViewRepresentable {
    @Environment(\.isEnabled) private var environmentEnabled
    let isRowInteractive: (Int) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isRowInteractive: isRowInteractive)
    }

    func makeNSView(context: Context) -> NSView {
        NativeTableHoverAnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        let enabled = environmentEnabled
        context.coordinator.isRowInteractive = { enabled && isRowInteractive($0) }
        context.coordinator.install(from: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var isRowInteractive: (Int) -> Bool {
            didSet { clearHover() }
        }

        private weak var tableView: NSTableView?
        private weak var clipView: NSClipView?
        private weak var hoveredRowView: NSTableRowView?
        private var hoveredRow: Int?
        private var decoration: NativeTableHoverDecorationView?
        private var trackingArea: NSTrackingArea?
        private var installationGeneration = 0
        private var tablePostedFrameChanges = false
        private var tablePostedBoundsChanges = false
        private var clipPostedBoundsChanges = false
        private var rowPostedFrameChanges = false
        private var rowPostedBoundsChanges = false

        init(isRowInteractive: @escaping (Int) -> Bool) {
            self.isRowInteractive = isRowInteractive
        }

        func install(from anchor: NSView) {
            installationGeneration += 1
            let generation = installationGeneration
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, self.installationGeneration == generation else { return }
                guard let table = anchor?.nearestTableView() else {
                    self.uninstall()
                    return
                }
                self.attach(to: table)
            }
        }

        func attach(to table: NSTableView) {
            guard tableView !== table else { return }
            uninstall()
            tableView = table
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil
            )
            trackingArea = area
            table.addTrackingArea(area)

            tablePostedFrameChanges = table.postsFrameChangedNotifications
            tablePostedBoundsChanges = table.postsBoundsChangedNotifications
            table.postsFrameChangedNotifications = true
            table.postsBoundsChangedNotifications = true
            observe(NSView.frameDidChangeNotification, object: table)
            observe(NSView.boundsDidChangeNotification, object: table)
            observe(NSTableView.selectionDidChangeNotification, object: table)
            observe(NSTableView.selectionIsChangingNotification, object: table)
            if let clip = table.enclosingScrollView?.contentView {
                clipView = clip
                clipPostedBoundsChanges = clip.postsBoundsChangedNotifications
                clip.postsBoundsChangedNotifications = true
                observe(NSView.boundsDidChangeNotification, object: clip)
            }
        }

        func uninstall() {
            installationGeneration += 1
            clearHover()
            NotificationCenter.default.removeObserver(self)
            if let tableView {
                if let trackingArea { tableView.removeTrackingArea(trackingArea) }
                tableView.postsFrameChangedNotifications = tablePostedFrameChanges
                tableView.postsBoundsChangedNotifications = tablePostedBoundsChanges
            }
            clipView?.postsBoundsChangedNotifications = clipPostedBoundsChanges
            tableView = nil
            clipView = nil
            trackingArea = nil
        }

        @objc func mouseEntered(_ event: NSEvent) { mouseMoved(event) }

        @objc func mouseMoved(_ event: NSEvent) {
            guard let table = tableView else { return }
            let point = table.convert(event.locationInWindow, from: nil)
            let row = table.row(at: point)
            guard table.isEnabled, table.visibleRect.contains(point), row >= 0, row < table.numberOfRows,
                  !table.selectedRowIndexes.contains(row),
                  table.delegate?.tableView?(table, isGroupRow: row) != true,
                  isRowInteractive(row),
                  let rowView = table.rowView(atRow: row, makeIfNecessary: false),
                  !rowView.isGroupRowStyle, !rowView.isSelected
            else {
                clearHover()
                return
            }
            guard hoveredRow != row || hoveredRowView !== rowView else { return }
            clearHover()
            hoveredRow = row
            hoveredRowView = rowView
            rowPostedFrameChanges = rowView.postsFrameChangedNotifications
            rowPostedBoundsChanges = rowView.postsBoundsChangedNotifications
            rowView.postsFrameChangedNotifications = true
            rowView.postsBoundsChangedNotifications = true
            observe(NSView.frameDidChangeNotification, object: rowView)
            observe(NSView.boundsDidChangeNotification, object: rowView)

            let feedback = NativeTableHoverDecorationView(frame: rowView.bounds)
            feedback.onDetach = { [weak self] in self?.clearHover() }
            decoration = feedback
            rowView.addSubview(feedback, positioned: .below, relativeTo: rowView.subviews.first)
            rowView.needsDisplay = true
        }

        @objc func mouseExited(_ event: NSEvent) { clearHover() }

        @objc private func tableDidChange(_ notification: Notification) { clearHover() }

        private func observe(_ name: Notification.Name, object: NSView) {
            NotificationCenter.default.addObserver(
                self, selector: #selector(tableDidChange(_:)), name: name, object: object
            )
        }

        private func clearHover() {
            decoration?.onDetach = nil
            decoration?.removeFromSuperview()
            decoration = nil
            if let row = hoveredRowView {
                NotificationCenter.default.removeObserver(
                    self, name: NSView.frameDidChangeNotification, object: row
                )
                NotificationCenter.default.removeObserver(
                    self, name: NSView.boundsDidChangeNotification, object: row
                )
                row.postsFrameChangedNotifications = rowPostedFrameChanges
                row.postsBoundsChangedNotifications = rowPostedBoundsChanges
                row.needsDisplay = true
            }
            hoveredRow = nil
            hoveredRowView = nil
        }
    }
}

/// This is the only temporary row decoration. It owns no row or table and
/// leaves the system background, selection, cells, and hit testing intact.
final class NativeTableHoverDecorationView: NSView {
    var onDetach: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window != nil, newWindow == nil { onDetach?() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()
        NSColor.controlAccentColor.withAlphaComponent(0.18).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

private final class NativeTableHoverAnchorView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension View {
    func nativeTableHoverHighlight(
        isRowInteractive: @escaping (Int) -> Bool = { _ in true }
    ) -> some View {
        background(NativeTableHoverAdapter(isRowInteractive: isRowInteractive))
    }
}
