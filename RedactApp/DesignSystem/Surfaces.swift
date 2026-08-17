import SwiftUI

/// The glass surface treatment — the single most recognisable element of the
/// app's visual language.
///
/// DEC-002 describes it precisely: `.ultraThinMaterial` over `BG.card`, a
/// **gradient** hairline border, and a deep low-opacity shadow. That is four
/// stacked layers in the right order, and getting the order wrong (material over
/// the border, border stroked rather than `strokeBorder`-ed, shadow on the
/// clipped shape) produces something that is *almost* right in a way reviewers
/// notice. This file is the one correct implementation; features call
/// ``SwiftUI/View/glassCard()`` and cannot get it wrong.
public struct GlassCard: ViewModifier {

    /// How much the surface is lifted off the background.
    public enum Elevation: Sendable, Equatable {
        /// The default: flat in the stack, deep card shadow.
        case resting
        /// Raised — hovered, focused, or the active item in a list. Lifts by
        /// ``Token/raiseOffset`` and blooms the accent glow, matching the HTML.
        case raised
        /// Pressed — sinks back down and tightens the shadow, so touch-down reads
        /// as the surface moving *toward* the finger.
        case pressed
    }

    private let elevation: Elevation
    private let cornerRadius: CGFloat
    private let padding: CGFloat?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        elevation: Elevation = .resting,
        cornerRadius: CGFloat = Token.Radius.card,
        padding: CGFloat? = Token.Space.md
    ) {
        self.elevation = elevation
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    public func body(content: Content) -> some View {
        content
            .padding(padding ?? 0)
            .background(fill)
            .overlay(border)
            .clipShape(shape)
            .shadow(shadowRecipe)
            .scaleEffect(elevation == .pressed ? 0.985 : 1)
            .offset(y: elevation == .raised ? Token.raiseOffset : 0)
            .animation(
                Motion.accessible(Motion.snappy, reduceMotion: reduceMotion),
                value: elevation
            )
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// Material *over* the card colour, not instead of it. The tint is what keeps
    /// the glass reading as navy rather than as neutral grey on a bright document.
    private var fill: some View {
        shape
            .fill(Token.BG.card.opacity(Token.Alpha.glassTint))
            .background(.ultraThinMaterial, in: shape)
    }

    /// `strokeBorder`, not `stroke` — the latter centres the line on the path and
    /// spills half a point outside the clip, which reads as a soft edge.
    private var border: some View {
        shape.strokeBorder(borderGradient, lineWidth: Token.Size.hairlineWidth)
    }

    /// The gradient hairline. At rest it is a near-invisible white ramp; raised,
    /// it picks up the brand gradient so the active surface identifies itself
    /// without any change in layout.
    private var borderGradient: LinearGradient {
        switch elevation {
        case .resting, .pressed:
            LinearGradient(
                colors: [Token.Line.strong, Token.Line.hairline],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .raised:
            LinearGradient(
                colors: [
                    Token.Accent.violetLight.opacity(0.55),
                    Token.Accent.amberLight.opacity(0.35)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var shadowRecipe: Token.Shadow.Recipe {
        switch elevation {
        case .resting: Token.Shadow.card
        case .raised: Token.Shadow.glow
        case .pressed: Token.Shadow.pressed
        }
    }
}

// MARK: - Application

public extension View {
    /// Applies the app's glass card treatment.
    ///
    /// - Parameters:
    ///   - elevation: resting, raised, or pressed. Animating this value is the
    ///     intended way to show interaction — do not hand-roll a scale or shadow.
    ///   - cornerRadius: defaults to ``Token/Radius/card``.
    ///   - padding: inner padding; pass `nil` for edge-to-edge content such as an
    ///     image or a document thumbnail.
    func glassCard(
        elevation: GlassCard.Elevation = .resting,
        cornerRadius: CGFloat = Token.Radius.card,
        padding: CGFloat? = Token.Space.md
    ) -> some View {
        modifier(GlassCard(elevation: elevation, cornerRadius: cornerRadius, padding: padding))
    }

    /// Applies a ``Token/Shadow/Recipe``.
    ///
    /// Exists so no view ever spells out a raw radius/offset pair — `CLAUDE.md`
    /// rule 3 covers depth just as much as colour.
    func shadow(_ recipe: Token.Shadow.Recipe) -> some View {
        shadow(color: recipe.color, radius: recipe.radius, x: recipe.x, y: recipe.y)
    }

    /// A hairline-bordered glass capsule — the shape used for pills, the privacy
    /// note, and any inline chip.
    func glassCapsule() -> some View {
        background(Capsule().fill(Token.BG.card.opacity(Token.Alpha.glassTint)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    LinearGradient(
                        colors: [Token.Line.strong, Token.Line.hairline],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: Token.Size.hairlineWidth
                )
            )
            .clipShape(Capsule())
    }
}
