import SwiftUI

struct InteractiveHoverState: Equatable {
    let isVisible: Bool
    let usesAnimatedTransition: Bool

    static func resolve(
        isHovering: Bool,
        explicitEnabled: Bool,
        environmentEnabled: Bool,
        reduceMotion: Bool
    ) -> InteractiveHoverState {
        InteractiveHoverState(
            isVisible: isHovering && explicitEnabled && environmentEnabled,
            usesAnimatedTransition: !reduceMotion
        )
    }
}

extension View {
    func interactiveHover(
        isEnabled: Bool = true,
        cornerRadius: CGFloat = 8
    ) -> some View {
        modifier(InteractiveHoverModifier(isEnabled: isEnabled, cornerRadius: cornerRadius))
    }
}

private struct InteractiveHoverModifier: ViewModifier {
    @Environment(\.isEnabled) private var environmentEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let isEnabled: Bool
    let cornerRadius: CGFloat

    private var state: InteractiveHoverState {
        InteractiveHoverState.resolve(
            isHovering: isHovering,
            explicitEnabled: isEnabled,
            environmentEnabled: environmentEnabled,
            reduceMotion: reduceMotion
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if state.isVisible {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                        }
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .animation(
                state.usesAnimatedTransition ? .easeOut(duration: 0.12) : nil,
                value: state.isVisible
            )
            .onHover { isHovering = $0 }
    }
}
