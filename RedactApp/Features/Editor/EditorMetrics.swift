import SwiftUI

/// Editor-only measurements and colour roles, all derived from `Token`.
///
/// `CLAUDE.md` rule 3 bans bare numbers in views. The editor needs a handful of values the global
/// token set has no opinion about — how thick a detection outline is, how long a dash segment runs,
/// how close a hand-drawn edge has to be before it snaps. Those live here, expressed as multiples of
/// existing tokens rather than as new invented constants, so retuning the design language still
/// moves them and no view ever spells out a literal.
enum EditorMetric {

    /// Outline weight of an *enabled* detection box. Two hairlines: heavy enough to read as
    /// "selected" without colour, at any zoom.
    static let boxBorderStrong: CGFloat = Token.Size.hairlineWidth * 2

    /// Outline weight of a *disabled* detection box.
    static let boxBorderWeak: CGFloat = Token.Size.hairlineWidth

    /// Dash pattern for a disabled box. Dashed-versus-solid is the non-colour cue that carries the
    /// enabled/disabled distinction for users who cannot separate violet from grey.
    static let boxDash: [CGFloat] = [Token.Space.xs, Token.Space.xs / 2]

    /// Corner radius of a detection or manual box. Smaller than a card: these sit on the document.
    static let boxRadius: CGFloat = Token.Radius.small / 2

    /// Edge length of a resize handle. Its *hit target* is padded to
    /// ``Token/Size/minimumHitTarget`` separately; this is only the visible dot.
    static let handleDot: CGFloat = Token.Space.sm

    /// How near a hand-drawn edge must come to a detected text edge before it snaps onto it,
    /// in content points at zoom 1.
    static let snapDistance: CGFloat = Token.Space.md

    /// Smallest hand-drawn box that is treated as a deliberate drag rather than a stray touch.
    static let minimumDraftSide: CGFloat = Token.Space.sm

    /// Height of the sweeping scanline band.
    static let scanlineHeight: CGFloat = Token.Space.lg

    /// Zoom limits for the page canvas.
    static let minimumZoom: CGFloat = 1
    static let maximumZoom: CGFloat = 4

    /// Opacity of the burnt-in preview fill once the bars land. Not fully opaque: the user must be
    /// able to see *that* something is under the bar while reviewing. The exported bar is opaque —
    /// that is `RedactionEngine`'s business, not the preview's.
    static let barPreviewOpacity: Double = 0.9

    /// Fill opacity of an enabled box before the bars land, and of a manual box.
    static let boxFillOpacity: Double = Token.Alpha.soft * 2
}

/// Which accent a detection is drawn in.
///
/// Colour groups the categories; it never *carries* the enabled/disabled state — that is the job of
/// stroke weight, dash, and the status glyph (`CLAUDE.md` rule 4). Only palette colours from
/// DEC-002 appear here.
enum DetectionPalette {

    /// The accent for a category. Financial and government identifiers get the hottest colour
    /// because they are the ones that must not be missed at a glance.
    static func accent(for kind: PIIKind) -> Color {
        switch kind {
        case .pan, .aadhaar, .creditCard, .gstin, .ifsc, .bankAccount:
            return Token.Accent.amber
        case .email, .phone, .address, .dateOfBirth:
            return Token.Accent.violet
        case .personName, .organisation, .place:
            return Token.Accent.violetLight
        case .custom:
            return Token.Accent.cyan
        }
    }

    /// The status glyph drawn on every box, so enabled/disabled survives greyscale, colour
    /// blindness, and a screenshot printed in black and white.
    static func statusSymbol(isEnabled: Bool) -> String {
        isEnabled ? "checkmark.circle.fill" : "circle.dashed"
    }
}
