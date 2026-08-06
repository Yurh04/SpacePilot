import AppKit
import SwiftUI

/// Adds a Finder double-click action to SwiftUI `List`/`Table` without placing
/// a competing gesture recognizer on their selectable cell content.
struct NativeTableDoubleClickAdapter: NSViewRepresentable {
    let urlAtRow: (Int) -> URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(urlAtRow: urlAtRow)
    }

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.urlAtRow = urlAtRow
        context.coordinator.install(from: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var urlAtRow: (Int) -> URL?

        private weak var tableView: NSTableView?
        private var previousTarget: AnyObject?
        private var previousAction: Selector?
        private var previousDoubleAction: Selector?

        private let reveal: (URL) -> Void

        init(
            urlAtRow: @escaping (Int) -> URL?,
            reveal: @escaping (URL) -> Void = { FinderReveal.reveal($0) }
        ) {
            self.urlAtRow = urlAtRow
            self.reveal = reveal
        }

        func install(from anchor: NSView) {
            DispatchQueue.main.async { [weak self, weak anchor] in
                guard let self, let anchor,
                      let tableView = anchor.nearestTableView()
                else { return }
                self.attach(to: tableView)
            }
        }

        func uninstall() {
            if let tableView, tableView.target === self {
                tableView.target = previousTarget
                tableView.action = previousAction
                tableView.doubleAction = previousDoubleAction
            }
            self.tableView = nil
            previousTarget = nil
            previousAction = nil
            previousDoubleAction = nil
        }

        @objc func tableAction(_ sender: NSTableView) {
            forward(previousAction, from: sender)
        }

        @objc func tableDoubleAction(_ sender: NSTableView) {
            forward(previousDoubleAction, from: sender)

            let row = sender.clickedRow
            guard row >= 0, let url = urlAtRow(row) else { return }
            reveal(url)
        }

        func attach(to newTableView: NSTableView) {
            guard tableView !== newTableView || newTableView.target !== self else {
                return
            }
            uninstall()

            tableView = newTableView
            previousTarget = newTableView.target
            previousAction = newTableView.action
            previousDoubleAction = newTableView.doubleAction
            newTableView.target = self
            newTableView.action = #selector(tableAction(_:))
            newTableView.doubleAction = #selector(tableDoubleAction(_:))
        }

        private func forward(_ action: Selector?, from sender: NSTableView) {
            guard let action else { return }
            NSApp.sendAction(action, to: previousTarget, from: sender)
        }

        var attachedTableViewForTesting: NSTableView? { tableView }
        var previousTargetForTesting: AnyObject? { previousTarget }
        var previousActionForTesting: Selector? { previousAction }
        var previousDoubleActionForTesting: Selector? { previousDoubleAction }
    }
}

private extension NSView {
    func nearestTableView() -> NSTableView? {
        let pointInWindow = convert(
            NSPoint(x: bounds.midX, y: bounds.midY),
            to: nil
        )
        var ancestor: NSView? = self

        while let candidateRoot = ancestor {
            let candidates = candidateRoot.descendantTableViews
            if let containing = candidates.first(where: { candidate in
                candidate.bounds.contains(candidate.convert(pointInWindow, from: nil))
            }) {
                return containing
            }
            if candidates.count == 1 {
                return candidates[0]
            }
            ancestor = candidateRoot.superview
        }
        return nil
    }

    var descendantTableViews: [NSTableView] {
        var result: [NSTableView] = []
        if let tableView = self as? NSTableView {
            result.append(tableView)
        }
        for subview in subviews {
            result.append(contentsOf: subview.descendantTableViews)
        }
        return result
    }
}

extension View {
    func nativeTableDoubleClickReveal(
        urlAtRow: @escaping (Int) -> URL?
    ) -> some View {
        background(NativeTableDoubleClickAdapter(urlAtRow: urlAtRow))
    }
}
