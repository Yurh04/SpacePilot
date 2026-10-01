import AppKit
import XCTest
@testable import SpacePilot

@MainActor
final class NativeTableHoverTests: XCTestCase {
    func testDisabledTableDoesNotHighlight() {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)
        fixture.table.isEnabled = false

        coordinator.mouseMoved(fixture.event(row: 1))

        XCTAssertNil(fixture.decoration(row: 1))
    }

    func testPointerMapsToInteractiveVisibleRow() throws {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        var evaluatedRows: [Int] = []
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: {
            evaluatedRows.append($0)
            return $0 == 2
        })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)

        coordinator.mouseMoved(fixture.event(row: 2))

        XCTAssertEqual(evaluatedRows, [2])
        let decoration = try XCTUnwrap(fixture.decoration(row: 2))
        XCTAssertEqual(decoration.frame, try fixture.rowView(2).bounds)
        XCTAssertNil(decoration.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertEqual(fixture.table.selectedRowIndexes, IndexSet())

        coordinator.mouseMoved(fixture.event(pointInTable: NSPoint(x: 10, y: -10)))
        XCTAssertNil(fixture.decoration(row: 2))
    }

    func testNonInteractiveAndGroupRowsDoNotHighlight() throws {
        let fixture = HoverTableFixture(groupRows: [1])
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { $0 != 2 })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)

        coordinator.mouseMoved(fixture.event(row: 0))
        XCTAssertNotNil(fixture.decoration(row: 0))
        coordinator.mouseMoved(fixture.event(row: 1))
        XCTAssertNil(fixture.decoration(row: 0))
        XCTAssertNil(fixture.decoration(row: 1))
        coordinator.mouseMoved(fixture.event(row: 2))
        XCTAssertNil(fixture.decoration(row: 2))
    }

    func testSelectedRowKeepsSystemSelectionAppearance() throws {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)
        let row = try fixture.rowView(1)
        let originalBackground = row.backgroundColor
        let originalSelectionStyle = row.selectionHighlightStyle

        coordinator.mouseMoved(fixture.event(row: 1))
        XCTAssertNotNil(fixture.decoration(row: 1))
        fixture.table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
        XCTAssertNil(fixture.decoration(row: 1))
        coordinator.mouseMoved(fixture.event(row: 1))

        XCTAssertNil(fixture.decoration(row: 1))
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.backgroundColor, originalBackground)
        XCTAssertEqual(row.selectionHighlightStyle, originalSelectionStyle)
    }

    func testMovingBetweenRowsClearsOnlyThePreviousRow() throws {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)
        let untouched = try fixture.rowView(3)
        let unrelatedView = NSView(frame: untouched.bounds)
        untouched.addSubview(unrelatedView)

        coordinator.mouseMoved(fixture.event(row: 0))
        let firstDecoration = try XCTUnwrap(fixture.decoration(row: 0))
        coordinator.mouseMoved(fixture.event(row: 0))
        XCTAssertTrue(fixture.decoration(row: 0) === firstDecoration)
        coordinator.mouseMoved(fixture.event(row: 2))

        XCTAssertNil(firstDecoration.superview)
        XCTAssertNil(fixture.decoration(row: 0))
        XCTAssertNotNil(fixture.decoration(row: 2))
        XCTAssertTrue(unrelatedView.superview === untouched)
        XCTAssertNil(fixture.decoration(row: 3))
    }

    func testExitReloadScrollAndDismantleClearHoverState() throws {
        let fixture = HoverTableFixture(rowCount: 30)
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        coordinator.attach(to: fixture.table)
        let originalTrackingCount = fixture.table.trackingAreas.count - 1

        coordinator.mouseMoved(fixture.event(row: 1))
        coordinator.mouseExited(fixture.event(row: 1))
        XCTAssertNil(fixture.decoration(row: 1))

        coordinator.mouseMoved(fixture.event(row: 1))
        let reloadedRow = try fixture.rowView(1)
        XCTAssertNotNil(fixture.decoration(row: 1))
        fixture.table.reloadData()
        fixture.table.layoutSubtreeIfNeeded()
        XCTAssertFalse(reloadedRow.subviews.contains { $0 is NativeTableHoverDecorationView })

        let scrolledRow = try fixture.rowView(1)
        coordinator.mouseMoved(fixture.event(row: 1))
        XCTAssertNotNil(fixture.decoration(row: 1))
        fixture.scroll.contentView.scroll(to: NSPoint(x: 0, y: 400))
        fixture.scroll.reflectScrolledClipView(fixture.scroll.contentView)
        fixture.table.layoutSubtreeIfNeeded()
        XCTAssertFalse(scrolledRow.subviews.contains { $0 is NativeTableHoverDecorationView })

        coordinator.mouseMoved(fixture.event(row: 20))
        let dismantledRow = try fixture.rowView(20)
        XCTAssertNotNil(fixture.decoration(row: 20))
        coordinator.uninstall()
        XCTAssertFalse(dismantledRow.subviews.contains { $0 is NativeTableHoverDecorationView })
        XCTAssertEqual(fixture.table.trackingAreas.count, originalTrackingCount)
        coordinator.mouseMoved(fixture.event(row: 20))
        XCTAssertNil(fixture.decoration(row: 20))
    }

    func testRecycledRowViewCannotKeepTemporaryDecoration() throws {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)
        coordinator.mouseMoved(fixture.event(row: 1))
        let recycledRow = try fixture.rowView(1)
        let originalBackground = recycledRow.backgroundColor
        XCTAssertNotNil(fixture.decoration(row: 1))

        fixture.table.reloadData()
        fixture.recycledRow = recycledRow
        fixture.recycleAtRow = 3
        fixture.table.layoutSubtreeIfNeeded()
        let newRow = try fixture.rowView(3)

        XCTAssertTrue(newRow === recycledRow)
        XCTAssertFalse(newRow.subviews.contains { $0 is NativeTableHoverDecorationView })
        XCTAssertEqual(newRow.backgroundColor, originalBackground)
        XCTAssertNil(fixture.decoration(row: 1))
    }

    func testHoverAndDoubleClickAdaptersPreserveExistingActions() {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let target = HoverActionTarget()
        let originalAction = #selector(HoverActionTarget.singleAction(_:))
        let originalDoubleAction = #selector(HoverActionTarget.doubleAction(_:))
        fixture.table.target = target
        fixture.table.action = originalAction
        fixture.table.doubleAction = originalDoubleAction
        let hover = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        let doubleClick = NativeTableDoubleClickAdapter.Coordinator(urlAtRow: { _ in nil })

        hover.attach(to: fixture.table)
        doubleClick.attach(to: fixture.table)
        hover.mouseMoved(fixture.event(row: 1))
        doubleClick.tableAction(fixture.table)
        doubleClick.tableDoubleAction(fixture.table)
        XCTAssertEqual(target.singleCount, 1)
        XCTAssertEqual(target.doubleCount, 1)
        hover.uninstall()
        XCTAssertTrue(fixture.table.target === doubleClick)
        XCTAssertEqual(fixture.table.action, #selector(doubleClick.tableAction(_:)))
        XCTAssertEqual(fixture.table.doubleAction, #selector(doubleClick.tableDoubleAction(_:)))
        doubleClick.uninstall()

        XCTAssertTrue(fixture.table.target === target)
        XCTAssertEqual(fixture.table.action, originalAction)
        XCTAssertEqual(fixture.table.doubleAction, originalDoubleAction)
    }

    func testUpdatedPredicateAndRowBoundsChangesClearDecoration() throws {
        let fixture = HoverTableFixture()
        defer { fixture.close() }
        let coordinator = NativeTableHoverAdapter.Coordinator(isRowInteractive: { _ in true })
        defer { coordinator.uninstall() }
        coordinator.attach(to: fixture.table)
        coordinator.mouseMoved(fixture.event(row: 1))

        coordinator.isRowInteractive = { _ in false }
        XCTAssertNil(fixture.decoration(row: 1))
        coordinator.isRowInteractive = { _ in true }
        coordinator.mouseMoved(fixture.event(row: 1))
        let row = try fixture.rowView(1)
        row.setFrameSize(NSSize(width: row.frame.width + 1, height: row.frame.height))
        XCTAssertNil(fixture.decoration(row: 1))
    }
}

@MainActor
private final class HoverTableFixture: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
    let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 320, height: 110))
    let rowCount: Int
    let groupRows: IndexSet
    var recycledRow: NSTableRowView?
    var recycleAtRow: Int?

    init(rowCount: Int = 5, groupRows: IndexSet = []) {
        _ = NSApplication.shared
        self.rowCount = rowCount
        self.groupRows = groupRows
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 110),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        super.init()
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("content")))
        table.tableColumns[0].width = 320
        table.headerView = nil
        table.rowHeight = 20
        table.intercellSpacing = .zero
        table.delegate = self
        table.dataSource = self
        scroll.documentView = table
        window.contentView = scroll
        table.reloadData()
        table.layoutSubtreeIfNeeded()
    }

    func close() { window.close() }
    func numberOfRows(in tableView: NSTableView) -> Int { rowCount }
    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        groupRows.contains(row)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        NSTextField(labelWithString: "Row \(row)")
    }
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        if row == recycleAtRow, let recycledRow {
            self.recycledRow = nil
            return recycledRow
        }
        return NSTableRowView()
    }

    func rowView(_ row: Int) throws -> NSTableRowView {
        try XCTUnwrap(table.rowView(atRow: row, makeIfNecessary: true))
    }
    func decoration(row: Int) -> NativeTableHoverDecorationView? {
        table.rowView(atRow: row, makeIfNecessary: false)?.subviews
            .compactMap { $0 as? NativeTableHoverDecorationView }.first
    }
    func event(row: Int) -> NSEvent {
        let rect = table.rect(ofRow: row)
        return event(pointInTable: NSPoint(x: rect.midX, y: rect.midY))
    }
    func event(pointInTable: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(
            with: .mouseMoved, location: table.convert(pointInTable, to: nil),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        )!
    }
}

@MainActor
private final class HoverActionTarget: NSObject {
    var singleCount = 0
    var doubleCount = 0
    @objc func singleAction(_ sender: NSTableView) { singleCount += 1 }
    @objc func doubleAction(_ sender: NSTableView) { doubleCount += 1 }
}
