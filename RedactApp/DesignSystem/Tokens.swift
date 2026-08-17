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
