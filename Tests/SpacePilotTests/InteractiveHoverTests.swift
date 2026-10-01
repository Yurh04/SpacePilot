import AppKit
import SwiftUI
import XCTest
@testable import SpacePilot

@MainActor
final class InteractiveHoverTests: XCTestCase {
    func testHoverIsVisibleOnlyWhenPointerAndBothEnablementSourcesAllowIt() {
        XCTAssertFalse(state(hovering: false).isVisible)
        XCTAssertFalse(state(hovering: true, explicitEnabled: false).isVisible)
        XCTAssertFalse(state(hovering: true, environmentEnabled: false).isVisible)
        XCTAssertTrue(state(hovering: true).isVisible)
    }

    func testReduceMotionUsesNoAnimatedTransition() {
        XCTAssertFalse(state(hovering: true, reduceMotion: true).usesAnimatedTransition)
        XCTAssertTrue(state(hovering: true, reduceMotion: false).usesAnimatedTransition)
    }

    func testModifierDoesNotChangeIdealSize() {
        let plain = NSHostingView(rootView: Text("Hover me").fixedSize())
        let hovered = NSHostingView(rootView: Text("Hover me").fixedSize().interactiveHover())

        XCTAssertEqual(hovered.fittingSize.width, plain.fittingSize.width, accuracy: 0.5)
        XCTAssertEqual(hovered.fittingSize.height, plain.fittingSize.height, accuracy: 0.5)
    }

    private func state(
        hovering: Bool,
        explicitEnabled: Bool = true,
        environmentEnabled: Bool = true,
        reduceMotion: Bool = false
    ) -> InteractiveHoverState {
        InteractiveHoverState.resolve(
            isHovering: hovering,
            explicitEnabled: explicitEnabled,
            environmentEnabled: environmentEnabled,
            reduceMotion: reduceMotion
        )
    }
}
