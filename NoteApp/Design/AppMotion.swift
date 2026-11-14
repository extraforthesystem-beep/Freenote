import SwiftUI

/// The app's motion tokens, and the Reduce Motion rule that goes with them.
/// Movement becomes an instant change when Reduce Motion is on; only fades
/// still animate.
enum AppMotion {
    /// Small state changes: a toggle, a highlight, a chip appearing.
    static let quick: Animation = .snappy(duration: 0.18)

    /// Panels, bars and sheets-in-place sliding or resizing.
    static let standard: Animation = .smooth(duration: 0.25)

    /// A large move the eye must follow, such as a page jump or a card flip.
    static let emphasized: Animation = .spring(response: 0.35, dampingFraction: 0.82)

    /// Opacity only. The one animation that survives Reduce Motion.
    static let fade: Animation = .easeInOut(duration: 0.15)

    /// The animation to actually run: `nil` under Reduce Motion unless it is
    /// `fade`, which still reads because it does not move anything.
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion && animation != fade ? nil : animation
    }

    /// Runs `body` with the token, or with no animation under Reduce Motion.
    @MainActor
    static func animate(_ animation: Animation, reduceMotion: Bool, _ body: () -> Void) {
        withAnimation(resolved(animation, reduceMotion: reduceMotion), body)
    }
}

extension View {
    /// Applies the token's animation to `value`, respecting Reduce Motion, so
    /// call sites do not each have to read the environment.
    func appAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AppAnimationModifier(animation: animation, value: value))
    }
}

private struct AppAnimationModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(AppMotion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}
