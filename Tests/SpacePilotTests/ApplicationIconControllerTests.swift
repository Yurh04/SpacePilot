import AppKit
import XCTest
@testable import SpacePilot

final class ApplicationIconControllerTests: XCTestCase {
    @MainActor
    func testBothDockIconsUseSystemSizedTransparentMargins() async throws {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        var received: NSImage?
        let controller = ApplicationIconController { received = $0 }
        defer { controller.stop() }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            application.appearance = NSAppearance(named: appearance)
            controller.start(application: application)
            let image = try XCTUnwrap(received)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(image.tiffRepresentation)))
            let y = bitmap.pixelsHigh / 2
            let opaqueColumns = (0..<bitmap.pixelsWide).filter {
                (bitmap.colorAt(x: $0, y: y)?.alphaComponent ?? 0) > 0.5
            }
            let first = try XCTUnwrap(opaqueColumns.first)
            let last = try XCTUnwrap(opaqueColumns.last)
            // Native macOS rounded tiles occupy approximately 80% of the icon canvas.
            XCTAssertEqual(Double(first) / Double(bitmap.pixelsWide), 100.0 / 1024, accuracy: 0.005)
            XCTAssertEqual(Double(last + 1) / Double(bitmap.pixelsWide), 924.0 / 1024, accuracy: 0.005)
        }
    }

    @MainActor
    func testLiveAppearanceChangesUpdateIconAndStopReleasesObservation() async throws {
        let application = NSApplication.shared
        let originalAppearance = application.appearance
        defer { application.appearance = originalAppearance }
        application.appearance = NSAppearance(named: .aqua)
        var received: [Data] = []
        let controller = ApplicationIconController { image in
            if let data = image.tiffRepresentation { received.append(data) }
        }
        controller.start(application: application)
        for _ in 0..<20 { await Task.yield() }
        let light = try XCTUnwrap(received.last)
        application.appearance = NSAppearance(named: .darkAqua)
        for _ in 0..<20 { await Task.yield() }
        let dark = try XCTUnwrap(received.last)
        XCTAssertNotEqual(light, dark)
        application.appearance = NSAppearance(named: .aqua)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(received.last, light)
        controller.stop()
        let count = received.count
        application.appearance = NSAppearance(named: .darkAqua)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(received.count, count)
    }
}
