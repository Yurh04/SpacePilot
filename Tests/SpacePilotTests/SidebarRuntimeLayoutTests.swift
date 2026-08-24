import AppKit
import Foundation
import SpacePilotCore
import SwiftUI
import XCTest
@testable import SpacePilot

@MainActor
final class SidebarRuntimeLayoutTests: XCTestCase {
    func testAppRootKeepsNavigationSplitViewInsideANarrowRestoredWindow() throws {
        let model = AppModel(
            runtime: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { _, _ in [] }
        model.selection = .applications

        let controller = NSHostingController(rootView: AppWindowContent(model: model))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 806, height: 607),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.setContentSize(NSSize(width: 806, height: 607))
        controller.view.frame = NSRect(x: 0, y: 0, width: 806, height: 607)
        window.layoutIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            controller.view.bounds.width,
            806,
            accuracy: 0.5,
            "The regression fixture must remain at the width visible in the report"
        )

        let rootSplitView = try XCTUnwrap(
            firstSubview(in: controller.view) { $0 is NSSplitView }
        )
        let splitFrame = rootSplitView.convert(rootSplitView.bounds, to: controller.view)
        XCTAssertGreaterThanOrEqual(
            splitFrame.minX,
            0,
            "The root split view must not overflow the window's leading edge"
        )
        XCTAssertLessThanOrEqual(
            splitFrame.maxX,
            controller.view.bounds.maxX,
            "The root split view must not overflow the window's trailing edge"
        )

        let sidebarCells = allSubviews(in: controller.view).filter {
            String(describing: type(of: $0)).hasPrefix("CellHostingView")
        }
        XCTAssertFalse(sidebarCells.isEmpty)
        for cell in sidebarCells {
            let frame = cell.convert(cell.bounds, to: controller.view)
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                controller.view.bounds.minX,
                "Sidebar icons and labels must stay visible at the leading edge"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                controller.view.bounds.maxX,
                "Sidebar rows must stay visible at the trailing edge"
            )
        }
    }

    func testApplicationSplitViewsStayInsideANarrowWindow() async throws {
        let model = AppModel(
            runtime: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { _, _ in [] }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: nil,
            items: [],
            applications: [
                ApplicationRecord(
                    name: "Example",
                    bundleIdentifier: "com.example.Example",
                    version: "1",
                    url: URL(fileURLWithPath: "/Applications/Example.app"),
                    executableURL: nil,
                    allocatedSize: 1
                )
            ],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        await model.applySnapshotForTesting(snapshot)
        try await waitForProjection(snapshot.id, in: model)
        model.selection = .applications

        let hostingView = NSHostingView(rootView: AppRootView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 806, height: 607)
        hostingView.layoutSubtreeIfNeeded()

        let splitViews = allSubviews(in: hostingView).compactMap { $0 as? NSSplitView }
        XCTAssertGreaterThanOrEqual(splitViews.count, 2)
        for splitView in splitViews {
            let frame = splitView.convert(splitView.bounds, to: hostingView)
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                hostingView.bounds.minX,
                "Every application split view must stay inside the leading edge"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                hostingView.bounds.maxX,
                "Every application split view must stay inside the trailing edge"
            )
        }
    }

    func testStorageSplitViewsStayInsideANarrowWindow() async throws {
        let model = AppModel(
            runtime: nil,
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { _, _ in [] }
        let snapshot = ScanSnapshot(
            completedAt: .now,
            volume: VolumeRecord(
                url: URL(fileURLWithPath: "/"),
                name: "Disk",
                totalCapacity: 1_000,
                availableCapacity: 500
            ),
            items: [
                ScannedItem(
                    url: URL(fileURLWithPath: "/Users/test/Library/Caches/example"),
                    logicalSize: 100,
                    allocatedSize: 100,
                    category: .cache,
                    risk: .safe,
                    explanation: "Fixture"
                )
            ],
            applications: [],
            aiApplications: [],
            plugins: [],
            skills: [],
            coverage: .complete
        )
        await model.applySnapshotForTesting(snapshot)
        try await waitForProjection(snapshot.id, in: model)
        model.selection = .storage

        let hostingView = NSHostingView(rootView: AppRootView(model: model))
        hostingView.frame = NSRect(x: 0, y: 0, width: 806, height: 607)
        hostingView.layoutSubtreeIfNeeded()

        let splitViews = allSubviews(in: hostingView).compactMap { $0 as? NSSplitView }
        XCTAssertGreaterThanOrEqual(splitViews.count, 2)
        for splitView in splitViews {
            let frame = splitView.convert(splitView.bounds, to: hostingView)
            XCTAssertGreaterThanOrEqual(
                frame.minX,
                hostingView.bounds.minX,
                "Every storage split view must stay inside the leading edge"
            )
            XCTAssertLessThanOrEqual(
                frame.maxX,
                hostingView.bounds.maxX,
                "Every storage split view must stay inside the trailing edge"
            )
        }
    }

    private func waitForProjection(
        _ snapshotID: UUID,
        in model: AppModel
    ) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if model.projection?.snapshotID == snapshotID {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("Timed out waiting for the projection")
    }

    private func allSubviews(in view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(allSubviews(in:))
    }

    private func firstSubview(
        in view: NSView,
        matching predicate: (NSView) -> Bool
    ) -> NSView? {
        if predicate(view) {
            return view
        }
        for subview in view.subviews {
            if let match = firstSubview(in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }
}
