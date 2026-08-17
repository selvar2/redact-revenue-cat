import SwiftUI

/// The app's motion vocabulary, and the guardrail that keeps it accessible.
///
/// `CLAUDE.md` rule 4 and DEC-002 both require that *every* animation degrade to
/// a cross-fade when `accessibilityReduceMotion` is on. Enforcing that by review
/// does not scale across parallel feature agents — one forgotten
/// `withAnimation(.spring)` is a silent accessibility regression that nothing in
/// `verify.sh` catches.
///
/// So the rule is expressed as API instead: feature code never names a raw
/// `Animation`. It reads ``SwiftUI/EnvironmentValues/accessibleAnimation`` (or
/// calls ``SwiftUI/View/accessibleAnimation(_:value:)``) and gets back either the
/// intended curve or the cross-fade, decided for it.
public enum Motion {

    // MARK: - Curves

    /// The signature curve — DEC-002's `cubic-bezier(.2, .8, .2, 1)`.
    /// Aliases ``Token/spring`` so there is exactly one definition of "our easing".
    public static let standard = Token.spring

    /// A snappier spring for direct manipulation: press states, toggles, chips.
    /// Direct-touch feedback must land faster than ``standard`` or it reads as lag.
    public static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.82)

    /// A softer, longer settle for large surfaces entering or leaving — sheets,
    /// full-screen results — where ``standard`` looks abrupt at scale.
    public static let gentle = Animation.spring(response: 0.62, dampingFraction: 0.88)

    /// Meter and progress fills. DEC-002 specifies ~1.1s.
    public static let meter = Animation.easeInOut(duration: 1.1)

    /// The ambient background drift: 16s, ease-in-out, alternating.
    /// Slow enough to feel alive without pulling attention off the document.
    public static let ambientDrift = Animation.easeInOut(duration: 16)
        .repeatForever(autoreverses: true)

    /// The universal reduced-motion substitute: a plain opacity cross-fade with
    /// no travel, no scale, no spring overshoot.
    ///
    /// Deliberately *not* `nil`. Removing animation entirely makes state changes
    /// snap, which reads as a glitch; a short fade preserves the sense of cause
    /// and effect that the motion was carrying.
    public static let crossFade = Animation.easeInOut(duration: 0.18)

    // MARK: - Durations

    /// Named durations for the rare case a view must schedule around an animation
    /// (for example, firing a haptic on the frame the redaction bars land).
    public enum Duration {
        public static let crossFade: TimeInterval = 0.18
        public static let snappy: TimeInterval = 0.28
        public static let standard: TimeInterval = 0.45
        public static let meter: TimeInterval = 1.1
    }

    // MARK: - Transitions

    /// The transition to pair with ``standard`` for content appearing in place.
    /// Collapses to a pure fade under reduced motion.
    public static func contentTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .bottom))
    }

    /// The transition for a scaled-in element (badges, detection markers).
    public static func popTransition(reduceMotion: Bool) -> AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .scale(scale: 0.92, anchor: .center))
    }

    /// Resolves an intended animation against the user's reduced-motion setting.
    ///
    /// Free function form, for the handful of call sites that hold the flag
    /// directly rather than reading the environment.
    public static func accessible(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? crossFade : animation
    }
}

// MARK: - Environment access

public extension EnvironmentValues {
    /// Resolves any intended animation against the current reduced-motion setting.
    ///
    /// Reads as `accessibleAnimation(Motion.standard)` at the call site and can
    /// be handed straight to `.animation(_:value:)` or `withAnimation`, so the
    /// accessible path is also the shortest path to write.
    var accessibleAnimation: @Sendable (Animation) -> Animation? {
        let reduceMotion = accessibilityReduceMotion
        return { reduceMotion ? Motion.crossFade : $0 }
    }
}

// MARK: - View sugar

public extension View {
    /// Animates `value` changes with `animation`, cross-fading instead when the
    /// user has asked for reduced motion.
    ///
    /// Prefer this over `.animation(_:value:)`, which has no way to know about
    /// the accessibility setting.
    func accessibleAnimation<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(AccessibleAnimationModifier(animation: animation, value: value))
    }

    /// Applies a transition that collapses to a fade under reduced motion.
    func accessibleTransition(_ build: @escaping (Bool) -> AnyTransition) -> some View {
        modifier(AccessibleTransitionModifier(build: build))
    }
}

private struct AccessibleAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.accessible(animation, reduceMotion: reduceMotion), value: value)
    }
}

private struct AccessibleTransitionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let build: (Bool) -> AnyTransition

    func body(content: Content) -> some View {
        content.transition(build(reduceMotion))
    }
}
