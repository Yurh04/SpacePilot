import AppKit

/// Public-AppKit traversal shared by native adapters for SwiftUI Lists/Tables.
extension NSView {
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

    private var descendantTableViews: [NSTableView] {
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
