import SwiftUI

/// A gradient-soft filled rounded square holding an SF Symbol.
///
/// This is the app's most repeated visual atom — it fronts every list row, every
/// empty state, every settings entry. It exists as a component because the
/// treatment is a specific stack (soft gradient fill, hairline border, gradient
/// *foreground* on the glyph) that looks wrong if any layer is dropped, and
/// because the glyph is decorative in almost every context: the well must default
/// to being invisible to VoiceOver so screen-reader users do not hear "document
/// viewfinder" before the row's actual label.
public struct IconWell: View {

    /// How the glyph is painted.
    public enum Tint: Sendable, Equatable {
        /// Brand gradient glyph over the soft gradient fill. The default.
        case gradient
        /// Muted monochrome — inactive or secondary rows.
        case muted
        /// Solid white glyph over a fully saturated gradient fill, for the one
        /// icon on a screen that must read as the subject rather than a bullet.
        case solid
    }

    private let systemName: String
    private let size: CGFloat
    private let tint: Tint
    private let accessibilityLabelText: String?

    @ScaledMetric(relativeTo: .body) private var scale: CGFloat = 1

    /// - Parameters:
    ///   - systemName: SF Symbol name.
    ///   - size: edge length before Dynamic Type scaling. Defaults to
    ///     ``Token/Size/iconWell``, which is also the minimum hit target — so a
    ///     well used as a button target is already large enough.
    ///   - accessibilityLabel: pass a label **only** when the icon carries meaning
    ///     no adjacent text conveys. Leave `nil` (the default) and the well is
    ///     hidden from VoiceOver, which is correct for decorative use.
    public init(
        _ systemName: String,
        size: CGFloat = Token.Size.iconWell,
        tint: Tint = .gradient,
        accessibilityLabel: String? = nil
    ) {
        self.systemName = systemName
        self.size = size
        self.tint = tint
        self.accessibilityLabelText = accessibilityLabel
    }

    public var body: some View {
        let side = size * scale

        RoundedRectangle(cornerRadius: Token.Radius.small * scale, style: .continuous)
            .fill(fill)
            .frame(width: side, height: side)
            .overlay(
                RoundedRectangle(cornerRadius: Token.Radius.small * scale, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: Token.Size.hairlineWidth)
            )
            .overlay(glyph(side: side))
            .accessibilityElement(children: .ignore)
            .modifier(WellAccessibility(label: accessibilityLabelText))
    }

    @ViewBuilder
    private func glyph(side: CGFloat) -> some View {
        let image = Image(systemName: systemName)
            .font(.system(size: side * 0.44, weight: .semibold))

        switch tint {
        case .gradient: image.foregroundStyle(Token.gradient)
        case .muted: image.foregroundStyle(Token.Text.muted)
        case .solid: image.foregroundStyle(.white)
        }
    }

    /// Type-erased because the three cases are two different concrete
    /// `ShapeStyle` types; `ViewBuilder` cannot unify them the way it does views.
    private var fill: AnyShapeStyle {
        switch tint {
        case .gradient: AnyShapeStyle(Token.gradientSoft)
        case .muted: AnyShapeStyle(Token.BG.raised)
        case .solid: AnyShapeStyle(Token.gradient)
        }
    }

    private var borderColor: Color {
        switch tint {
        case .gradient: Token.Accent.violet.opacity(0.28)
        case .muted: Token.Line.hairline
        case .solid: .white.opacity(0.25)
        }
    }
}

/// Applies a VoiceOver label, or hides the element when there is nothing
/// meaningful to say. Extracted so the branch is not repeated at every call site.
private struct WellAccessibility: ViewModifier {
    let label: String?

    func body(content: Content) -> some View {
        if let label {
            content.accessibilityLabel(label)
        } else {
            content.accessibilityHidden(true)
        }
    }
}

#Preview("IconWell") {
    HStack(spacing: Token.Space.md) {
        IconWell("doc.viewfinder")
        IconWell("photo.on.rectangle", tint: .muted)
        IconWell("eye.slash.fill", size: 64, tint: .solid)
    }
    .padding(Token.Space.lg)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .ambientBackground()
    .preferredColorScheme(.dark)
}
