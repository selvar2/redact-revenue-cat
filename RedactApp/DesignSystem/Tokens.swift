import SwiftUI

/// Design tokens — the single source of truth for the app's visual language.
///
/// Ported from the DIVS executive-overview HTML. Every value here is specified in
/// `docs/memory/decisions/DEC-002-design-language.md`; that document is the spec,
/// this file is its implementation.
///
/// `CLAUDE.md` rule 3: no view may hardcode a colour, font, radius, spacing value,
/// or animation curve. If a token is missing, add it here first.
///
/// - Note: This is the Phase 0 seed. The `design-system` agent expands it in Phase 1
///   with surfaces, typography scale, and motion modifiers.
public enum Token {

    // MARK: - Colour

    /// Background ramp, deepest to most raised.
    public enum BG {
        /// `#0A0E1A` — app background.
        public static let base = Color(hex: 0x0A0E1A)
        /// `#0E1424` — section background.
        public static let section = Color(hex: 0x0E1424)
        /// `#131A2E` — card surface.
        public static let card = Color(hex: 0x131A2E)
        /// `#1A2340` — raised / active card surface.
        public static let raised = Color(hex: 0x1A2340)
    }

    /// Accent ramp. Violet is primary, amber is the gradient terminus.
    public enum Accent {
        public static let violet = Color(hex: 0xA855F7)
        public static let violetLight = Color(hex: 0xC084FC)
        public static let amber = Color(hex: 0xFF6B3D)
        public static let amberLight = Color(hex: 0xFF8C5A)
        /// Reserved for rare highlights only — overuse dilutes the two-colour identity.
        public static let cyan = Color(hex: 0x22D3EE)
    }

    public enum Text {
        public static let primary = Color(hex: 0xEDF1FA)
        public static let muted = Color(hex: 0x93A0BF)
        public static let faint = Color(hex: 0x5A6782)
    }

    public enum Line {
        public static let hairline = Color.white.opacity(0.07)
        public static let strong = Color.white.opacity(0.12)
    }

    // MARK: - Gradient

    /// The app's signature 135° violet→amber gradient.
    public static let gradient = LinearGradient(
        colors: [Accent.violet, Accent.amber],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// The same gradient at 16% — icon wells and inactive fills.
    public static let gradientSoft = LinearGradient(
        colors: [Accent.violet.opacity(0.16), Accent.amber.opacity(0.16)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Shape

    public enum Radius {
        public static let card: CGFloat = 20
        public static let control: CGFloat = 13
        public static let small: CGFloat = 9
    }

    public enum Space {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 20
        public static let lg: CGFloat = 32
        public static let xl: CGFloat = 48
    }

    // MARK: - Motion

    /// The HTML's signature `cubic-bezier(.2, .8, .2, 1)` — fast out, gentle settle.
    /// Default for every transition in the app.
    public static let spring = Animation.spring(response: 0.45, dampingFraction: 0.8)

    // MARK: - Depth

    /// Shadow recipes from DEC-002.
    ///
    /// CSS box-shadows carry a *spread* term that SwiftUI's `.shadow` has no
    /// equivalent for, so each recipe below is the closest visual match rather than
    /// an arithmetic translation. They are tokens precisely so that tuning happens
    /// here once instead of drifting across a dozen views.
    public enum Shadow {
        /// A shadow recipe. `Sendable` because tokens are read from any actor.
        public struct Recipe: Sendable, Equatable {
            public let color: Color
            public let radius: CGFloat
            public let x: CGFloat
            public let y: CGFloat

            public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat) {
                self.color = color
                self.radius = radius
                self.x = x
                self.y = y
            }
        }

        /// `0 24px 60px -24px rgba(0,0,0,.7)` — the deep, soft card shadow.
        public static let card = Recipe(color: .black.opacity(0.7), radius: 26, y: 16)

        /// The card shadow tightened for a pressed control: less lift, less blur.
        public static let pressed = Recipe(color: .black.opacity(0.55), radius: 12, y: 6)

        /// `0 30px 60px -26px rgba(168,85,247,.55)` — the accent bloom on active surfaces.
        public static let glow = Recipe(color: Accent.violet.opacity(0.45), radius: 28, y: 16)

        /// The violet bloom under the app mark — the same recipe as ``glow`` but
        /// stronger and lifted less, because the mark floats over the base ramp
        /// rather than over a card.
        public static let mark = Recipe(color: Accent.violet.opacity(Alpha.markGlow), radius: 28, y: 10)
    }

    /// Vertical lift applied to a raised surface, matching the HTML's
    /// `translateY(-6px)` hover state.
    public static let raiseOffset: CGFloat = -6

    // MARK: - Layout

    public enum Size {
        /// Apple's HIG minimum touch target. Every control in `Components/` is
        /// padded up to this even when its glyph is smaller.
        public static let minimumHitTarget: CGFloat = 44
        /// Edge length of a standard `IconWell`.
        public static let iconWell: CGFloat = 44
        /// Stroke width for every hairline border; one value keeps the glass
        /// treatment consistent across cards, pills, and buttons.
        public static let hairlineWidth: CGFloat = 1
        /// Edge length of the app mark (the gradient tile bearing the eye glyph).
        /// Scaled with `@ScaledMetric` at the point of use so it tracks Dynamic Type.
        public static let mark: CGFloat = 72
        /// Width of a small page thumbnail shown beside a line or two of text — the
        /// export screen's markup rows, and anywhere else a page needs to be
        /// recognisable rather than readable. Scale it with `@ScaledMetric` at the
        /// point of use, or it becomes a fixed stamp beside text that grows.
        public static let thumbnailSmall: CGFloat = 72
    }

    public enum Layout {
        /// Maximum measure for a paragraph of running text. Beyond this the eye
        /// loses the line start on return; DEC-002 sets it once for every surface.
        public static let proseWidth: CGFloat = 320
    }

    // MARK: - Opacity

    /// Named opacities, so views never spell out a bare `0.16`.
    public enum Alpha {
        /// The soft-gradient level from DEC-002.
        public static let soft: Double = 0.16
        /// Disabled controls.
        public static let disabled: Double = 0.4
        /// The material tint layered over `BG.card` in glass surfaces.
        public static let glassTint: Double = 0.55
        /// Strength of the primary (violet) ambient radial glow in the hero layer.
        public static let glowPrimary: Double = 0.22
        /// Strength of the secondary (amber) ambient radial glow.
        public static let glowSecondary: Double = 0.18
        /// Strength of the coloured shadow cast by the app mark.
        public static let markGlow: Double = 0.5
    }
}

// MARK: - Hex convenience

extension Color {
    /// Builds a colour from a 24-bit RGB literal, so tokens read the same as the
    /// hex values in DEC-002 and can be diffed against the source HTML by eye.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
