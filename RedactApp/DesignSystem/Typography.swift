import SwiftUI

/// The app's type scale.
///
/// This type exists so that swapping the real brand faces in is a *one-line*
/// change. DEC-002 specifies Space Grotesk for display and Inter for body, but
/// neither is bundled yet and DEC-004 forbids fetching them at runtime. Rather
/// than sprinkle `.font(.system(...))` across every view — which would make the
/// eventual swap a repo-wide find-and-replace — every style resolves through
/// ``Typography/resolve(size:weight:design:)``. When the `.otf` files land,
/// that one function starts returning `Font.custom(_:size:relativeTo:)` and the
/// entire app re-types itself.
///
/// It also exists to make Dynamic Type unskippable. DEC-002 pins specific point
/// sizes, and a raw `Font.system(size:)` ignores the user's text-size setting
/// entirely — which would fail `CLAUDE.md` rule 4. Styles are therefore applied
/// with ``SwiftUI/View/typeStyle(_:)``, which scales the pinned size against a
/// paired `Font.TextStyle` via `@ScaledMetric`.
public enum Typography {

    /// A single entry in the scale: a pinned size from DEC-002 plus the metrics
    /// needed to render and scale it faithfully.
    public struct Style: Sendable, Equatable {
        /// Base size in points at the default content-size category.
        public let size: CGFloat
        public let weight: Font.Weight
        public let design: Font.Design
        /// Letter-spacing. DEC-002 calls for tight tracking on large display type.
        public let tracking: CGFloat
        /// Extra leading. DEC-002 asks for 1.6–1.7 line-height on body copy;
        /// this is the delta over the font's natural line height.
        public let lineSpacing: CGFloat
        /// The system text style this scales against, so Dynamic Type ramps this
        /// style the way the user expects that role to ramp.
        public let textStyle: Font.TextStyle

        public init(
            size: CGFloat,
            weight: Font.Weight,
            design: Font.Design,
            tracking: CGFloat = 0,
            lineSpacing: CGFloat = 0,
            relativeTo textStyle: Font.TextStyle
        ) {
            self.size = size
            self.weight = weight
            self.design = design
            self.tracking = tracking
            self.lineSpacing = lineSpacing
            self.textStyle = textStyle
        }
    }

    // MARK: - Face selection

    /// Display face: headings, numerals, the brand mark.
    ///
    /// `.rounded` is the closest system stand-in for Space Grotesk's geometric,
    /// slightly humanist character. Swapping in the real face means returning
    /// `.custom("SpaceGrotesk-\(weight)", size: size, relativeTo: textStyle)` here.
    private static let displayDesign: Font.Design = .rounded

    /// Body face. `.default` (SF Pro) is a faithful stand-in for Inter — both are
    /// neutral grotesques tuned for screen reading.
    private static let bodyDesign: Font.Design = .default

    /// The single point where a `Style` becomes a `Font`.
    ///
    /// Every glyph in the app passes through here. That is the whole point.
    public static func resolve(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    // MARK: - Display scale

    /// The brand mark and first-run hero. Used once per screen at most.
    public static let displayXL = Style(
        size: 44, weight: .bold, design: displayDesign,
        tracking: -1.3, relativeTo: .largeTitle
    )

    /// Screen titles.
    public static let displayLarge = Style(
        size: 32, weight: .bold, design: displayDesign,
        tracking: -0.8, relativeTo: .title
    )

    /// Card headings and sheet titles.
    public static let title = Style(
        size: 24, weight: .semibold, design: displayDesign,
        tracking: -0.5, relativeTo: .title2
    )

    /// Sub-headings inside a card.
    public static let headline = Style(
        size: 18, weight: .semibold, design: displayDesign,
        tracking: -0.2, relativeTo: .headline
    )

    /// Large numerals — counts of detected PII, page totals, prices.
    ///
    /// Separate from ``displayLarge`` because it is monospaced-digit: a figure
    /// that animates upward must not reflow the layout on every tick.
    public static let numeral = Style(
        size: 34, weight: .semibold, design: displayDesign,
        tracking: -0.9, relativeTo: .title
    )

    /// The glyph inside the app mark. Sized as display type rather than as an
    /// icon so it ramps with Dynamic Type alongside the mark tile itself.
    public static let markGlyph = Style(
        size: 30, weight: .semibold, design: displayDesign,
        relativeTo: .largeTitle
    )

    // MARK: - Body scale

    /// Default running text. The 6pt line-spacing lands body copy near the
    /// 1.6 line-height DEC-002 asks for.
    public static let body = Style(
        size: 16, weight: .regular, design: bodyDesign,
        lineSpacing: 6, relativeTo: .body
    )

    /// Body text carrying emphasis — the active choice in a list, a selected rule.
    public static let bodyEmphasis = Style(
        size: 16, weight: .semibold, design: bodyDesign,
        lineSpacing: 6, relativeTo: .body
    )

    /// Secondary explanatory text under a heading or control.
    public static let callout = Style(
        size: 14, weight: .regular, design: bodyDesign,
        lineSpacing: 4, relativeTo: .callout
    )

    /// Button and pill labels.
    public static let label = Style(
        size: 15, weight: .semibold, design: bodyDesign,
        relativeTo: .subheadline
    )

    /// Captions, footnotes, the on-device privacy note.
    public static let caption = Style(
        size: 12, weight: .medium, design: bodyDesign,
        relativeTo: .caption
    )

    /// Section-header eyebrow text — small, wide-tracked, uppercase by convention.
    public static let overline = Style(
        size: 11, weight: .semibold, design: bodyDesign,
        tracking: 1.2, relativeTo: .caption2
    )
}

// MARK: - Application

/// Applies a ``Typography/Style`` with live Dynamic Type scaling.
///
/// A modifier rather than a plain `Font` because `@ScaledMetric` only works as a
/// property wrapper on a `View`/`ViewModifier` — that is the mechanism that makes
/// DEC-002's pinned point sizes respond to the user's text-size setting.
private struct TypeStyleModifier: ViewModifier {
    @ScaledMetric private var scaledSize: CGFloat
    private let style: Typography.Style

    init(_ style: Typography.Style) {
        self.style = style
        _scaledSize = ScaledMetric(wrappedValue: style.size, relativeTo: style.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(Typography.resolve(size: scaledSize, weight: style.weight, design: style.design))
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

public extension View {
    /// Types this view with a scale entry from ``Typography``.
    ///
    /// Prefer this over `.font(...)` everywhere — it is the only path that both
    /// honours Dynamic Type and survives the eventual brand-font swap.
    func typeStyle(_ style: Typography.Style) -> some View {
        modifier(TypeStyleModifier(style))
    }
}
